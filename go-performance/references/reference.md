# Go Performance Reference

Detailed code patterns, quantitative guidance, and version-specific features. Loaded on demand from `SKILL.md`.

## Allocation Optimization Patterns

### strings.Builder with pre-allocation

```go
var b strings.Builder
b.Grow(estimatedLen) // single allocation
for _, s := range parts {
    b.WriteString(s)
}
result := b.String() // zero-copy conversion via unsafe
```

`strings.Builder` avoids the `[]byte`-to-`string` copy that `bytes.Buffer.String()` incurs. Pre-allocating with `Grow()` avoids repeated growth allocations entirely.

### Append-style API signatures

Design hot-path functions to accept a destination buffer the caller can reuse:

```go
// Good: caller controls allocation
func Encode(dst []byte, src T) []byte {
    dst = append(dst, header...)
    dst = appendPayload(dst, src)
    return dst
}

// Usage with pooled buffer
bp := pool.Get().(*[]byte)
buf := (*bp)[:0]
buf = Encode(buf, item)
process(buf)
*bp = buf
pool.Put(bp)
```

### sync.Pool usage

```go
var bufPool = sync.Pool{
    New: func() any {
        b := make([]byte, 0, 4096)
        return &b
    },
}

func handle(r *http.Request) {
    bp := bufPool.Get().(*[]byte)
    buf := (*bp)[:0] // reset length, keep capacity
    defer func() {
        *bp = buf
        bufPool.Put(bp)
    }()
    // use buf...
}
```

Key rules:
- Pool **short-lived, frequently allocated** objects that dominate alloc profiles.
- Always **reset on Get or before Put** to avoid data leaks between requests. Either convention works; be consistent within a codebase.
- Never assume an object survives a GC cycle; handle the `New` case.
- Prefer pointer-like values to avoid boxing large values into `any`, which causes a heap allocation.

### Escape analysis verification

```bash
go build -gcflags="-m" ./pkg 2>&1 | grep "escapes to heap"
```

Common escape triggers and fixes:

| Trigger | Fix |
|---|---|
| Returning `&localVar` | Return by value; let caller take address if needed |
| Storing pointer in heap struct | Redesign to store value or index |
| Closure capturing local | Pass as function parameter instead |
| Interface boxing of large value | Use concrete type on hot path |
| `append` causing slice escape | Pre-allocate with known capacity |

### Slice pre-allocation

Slice capacity grows geometrically (the exact algorithm is a runtime implementation detail and may change across Go versions). Pre-allocating avoids this growth entirely:

```go
// Bad: O(log n) allocations and copies
var result []Item
for _, raw := range inputs {
    result = append(result, parse(raw))
}

// Good: single allocation
result := make([]Item, 0, len(inputs))
for _, raw := range inputs {
    result = append(result, parse(raw))
}
```

Use `slices.Grow(s, n)` to pre-grow capacity without appending dummy elements.

### Slice retention fix

A subslice keeps the entire backing array alive:

```go
// Bad: retains full 1MB buffer
func extract(buf []byte) []byte {
    return buf[10:20]
}

// Good: allows original buffer to be GC'd
func extract(buf []byte) []byte {
    out := make([]byte, 10)
    copy(out, buf[10:20])
    return out
}
```

This matters most for long-lived subslices of large read buffers, request bodies, or memory-mapped regions.

## Data Structure Performance

### Struct field ordering

On 64-bit systems, fields align to their type's natural boundary. Poor ordering wastes bytes in padding:

```go
// Bad: 24 bytes (7 bytes padding)
type Bad struct {
    a bool   // 1 + 7 padding
    b int64  // 8
    c bool   // 1 + 7 padding
}

// Good: 16 bytes (6 bytes padding, at end only)
type Good struct {
    b int64  // 8
    a bool   // 1
    c bool   // 1 + 6 padding
}
```

Rule of thumb: order fields from largest to smallest alignment. With millions of instances, this can save tens of megabytes.

### False sharing prevention

When goroutines write to different fields on the same 64-byte cache line, cache coherency traffic degrades performance:

```go
import "golang.org/x/sys/cpu"

type Counters struct {
    reads  int64
    _      cpu.CacheLinePad // forces 'writes' to a different cache line
    writes int64
}
```

False sharing can cause significant degradation under contention; measure with benchmarks. Only apply padding when profiling reveals cache contention on concurrent struct access.

### Map capacity hints

```go
m := make(map[string]int, expectedSize)
```

Even an approximate hint reduces rehash overhead. Go 1.24's Swiss Tables implementation significantly improved map performance (the Go blog reported major gains in microbenchmarks), but capacity hints still help by reducing initial growth steps.

## HTTP Client Tuning

The default `http.Transport` has defaults that hurt high-throughput applications:

```go
transport := &http.Transport{
    MaxIdleConns:        100,
    MaxIdleConnsPerHost: 100, // default is 2 -- far too low
    MaxConnsPerHost:     100,
    IdleConnTimeout:     90 * time.Second,
}
client := &http.Client{
    Transport: transport,
    Timeout:   10 * time.Second,
}
```

`MaxIdleConnsPerHost` defaults to **2**. Applications making many concurrent requests to the same backend will constantly create and tear down TCP connections instead of reusing them.

Always fully drain response bodies to enable connection reuse:

```go
defer resp.Body.Close()
io.Copy(io.Discard, resp.Body)
```

Go will not reuse a connection unless the body is fully consumed. Create separate `http.Client` instances for different backends to avoid connection pool cross-talk.

## Buffered I/O

- Default `bufio.Scanner` buffer: 64KB. Use `Scanner.Buffer()` to increase for large tokens.
- `io.ReadAll` reads everything into memory. Use `bufio.Reader` or fixed-size `io.Read` for large or untrusted inputs.
- Pool `bufio.Reader`/`bufio.Writer` via `sync.Pool` in high-connection servers.
- Go can use `sendfile`/`splice` on Linux for certain file-to-socket and socket-to-socket paths via `io.Copy` when concrete types support it. Use `io.Copy` (not manual read/write loops) to allow the runtime to apply zero-copy kernel transfers when possible.

## GC Tuning Details

### GOGC

Controls the target heap growth ratio. Default 100 means GC triggers when heap doubles since last collection:

```
Target heap = Live heap + (Live heap + GC roots) * GOGC / 100
```

Doubling GOGC halves GC CPU cost but doubles peak memory. Setting `GOGC=off` disables GC frequency targeting entirely (still constrained by GOMEMLIMIT if set).

### GOMEMLIMIT

Soft memory limit on total Go runtime memory (Go 1.19+). The GC becomes progressively more aggressive as usage approaches the limit.

```bash
# Container with 512 MiB limit
GOGC=100 GOMEMLIMIT=450MiB ./myapp

# Maximum GC efficiency in fixed-memory environment
GOGC=off GOMEMLIMIT=450MiB ./myapp
```

Set GOMEMLIMIT to **90-95% of container memory** to leave headroom for non-Go memory (cgo, kernel buffers, temporary spikes). Built-in thrashing protection limits GC CPU to ~50% over a `2 * GOMAXPROCS` CPU-second window.

### GC diagnostics

```bash
GODEBUG=gctrace=1 ./myapp        # GC event log to stderr
GODEBUG=schedtrace=1000 ./myapp  # scheduler state every 1000ms
```

For stable runtime metrics in production, prefer `runtime/metrics` over `runtime.ReadMemStats`.

### Ballast: obsolete

The ballast technique (`var _ = make([]byte, 1<<30)`) is fully replaced by `GOMEMLIMIT`. GOMEMLIMIT is portable, does not waste real memory, and is the officially supported mechanism. Do not use ballast in new code.

## PGO Workflow

Profile-Guided Optimization feeds production CPU profiles back to the compiler for 2-14% improvement.

### Step-by-step

1. Build and deploy without PGO.
2. Collect a representative CPU profile:
   ```bash
   curl -o cpu.pprof http://localhost:6060/debug/pprof/profile?seconds=30
   ```
3. Copy the profile to the main package directory as `default.pgo`.
4. Rebuild. The Go toolchain detects and uses `default.pgo` automatically.
5. Redeploy and re-measure.

### What PGO optimizes

- **Hot function inlining**: increases the inlining budget for functions that appear frequently in the profile.
- **Devirtualization**: replaces interface method calls with direct calls to the concrete type seen in the profile. This is critical because interface dispatch prevents inlining, which blocks further optimizations.
- **Code layout**: improves instruction cache utilization.

### Iterating

Update the profile periodically. Stale profiles still help (the hot paths rarely change completely) but fresh profiles capture new code paths. Keep `default.pgo` in version control.

## Concurrency Patterns

### Worker pool with backpressure

```go
func processAll(ctx context.Context, items []Item, workers int) error {
    g, ctx := errgroup.WithContext(ctx)
    work := make(chan Item)

    // Start fixed worker pool
    for range workers {
        g.Go(func() error {
            for item := range work {
                if err := process(ctx, item); err != nil {
                    return err
                }
            }
            return nil
        })
    }

    // Feed work; channel provides backpressure
    g.Go(func() error {
        defer close(work)
        for _, item := range items {
            select {
            case work <- item:
            case <-ctx.Done():
                return ctx.Err()
            }
        }
        return nil
    })

    return g.Wait()
}
```

Size CPU-bound pools to `runtime.GOMAXPROCS(0)`. I/O-bound pools can exceed CPU count; benchmark to find the sweet spot.

### Atomic operations for simple counters

```go
var counter atomic.Int64

counter.Add(1)       // lock-free increment
val := counter.Load() // lock-free read
```

Typed atomics (`atomic.Int64`, `atomic.Bool`, etc.) are clearer and safer than `atomic.AddInt64(&val, 1)`. Use atomics for simple counters and flags; use mutexes for protecting complex state.

### sync.Map usage (Go 1.24+)

`sync.Map` was significantly rewritten in Go 1.24. Disjoint key modifications now contend far less, and read-heavy workloads no longer need a ramp-up period.

Good use cases for `sync.Map`:
- Cache entries written once, read many times.
- Disjoint key sets accessed by different goroutines.
- Growing key sets where entries are rarely deleted.

For all other concurrent map patterns, a `sync.RWMutex`-guarded map or sharded map is typically faster.

## Compiler Optimization Details

### Inlining

Default inlining budget: **80** (a cost model, not line count). Functions exceeding budget are not inlined. PGO raises the budget for hot functions.

What increases inlining cost:
- `defer` statements
- `recover()` calls (prevents inlining entirely)
- Large function bodies
- Complex control flow

Verify inlining decisions:
```bash
go build -gcflags="-m" ./pkg 2>&1 | grep "can inline\|cannot inline"
```

### Bounds check elimination hints

The compiler eliminates bounds checks when it can prove safety. Help it by hoisting a single check:

```go
func process(s []byte) {
    _ = s[3] // prove s has at least 4 elements
    a := s[0] // no bounds check
    b := s[1] // no bounds check
    c := s[2] // no bounds check
    d := s[3] // no bounds check
    // ...
}
```

Verify with:
```bash
go build -gcflags="-d=ssa/check_bce/debug=1" ./pkg
```

### Compiler directives

| Directive | Purpose | Safety |
|---|---|---|
| `//go:noinline` | Prevent inlining | Safe; use only for benchmarking/debugging |
| `//go:noescape` | Mark pointer args as non-escaping | **Dangerous**; only for assembly-backed functions |
| `//go:nosplit` | Skip stack overflow check | **Dangerous**; runtime/low-level only |
| `//go:linkname` | Link to unexported symbol | **Fragile**; breaks across Go versions |

Do not use `//go:noescape` or `//go:nosplit` in application code. Misuse causes memory corruption or stack overflows.

## String and Byte Patterns

### String interning with unique (Go 1.23+)

The `unique` package provides canonical deduplication of values with automatic GC-aware cleanup:

```go
import "unique"

type Entry struct {
    Zone unique.Handle[string]
}

func newEntry(zone string) Entry {
    return Entry{Zone: unique.Make(zone)}
}

// Equality is a pointer comparison (constant time)
e1.Zone == e2.Zone
```

Useful when many identical strings exist (HTTP headers, DNS zones, log fields). The GC automatically cleans up unreferenced canonical values.

### Avoiding string/[]byte conversions

`string([]byte)` and `[]byte(string)` allocate and copy. The compiler optimizes some cases:

| Pattern | Allocates? |
|---|---|
| `m[string(b)]` lookup | No (compiler-optimized) |
| `switch string(b)` | No (compiler-optimized) |
| `s := string(b)` then use `s` | Yes |
| Concatenation `string(b) + s` | Yes |

For read-only, performance-critical use, `unsafe.String` and `unsafe.Slice` avoid copies but require extreme care regarding GC and string immutability.

## Weak References and Cleanups (Go 1.24+)

### weak.Pointer

```go
import "weak"

p := weak.Make(&myObj)
// ...
if obj := p.Value(); obj != nil {
    // object is still alive
}
```

Use for caches where entries should be evictable by GC. The pointer automatically becomes nil when the referent is collected.

### runtime.AddCleanup

Replaces `runtime.SetFinalizer` with a better API:

```go
runtime.AddCleanup(&obj, func(resourceID int) {
    releaseResource(resourceID)
}, obj.resourceID)
```

Advantages over `SetFinalizer`:
- Supports multiple cleanups per object.
- Handles cycles (finalizers cannot).
- Does not delay object collection.
- Faster than `SetFinalizer`.

## Green Tea GC

Redesigns GC scanning to process memory in contiguous 8 KiB spans rather than individual objects, improving scanning locality. Also enables hardware vector acceleration (AVX-512) on newer amd64 platforms (Intel Ice Lake+ / AMD Zen 4+).

| Version | Status | Flag |
|---|---|---|
| Go 1.25 | Experimental, opt-in | `GOEXPERIMENT=greenteagc` to enable |
| Go 1.26 | **Default**, opt-out available | `GOEXPERIMENT=nogreenteagc` to disable |

The Go team reports ~10-40% reduction in GC overhead depending on workload. The opt-out is expected to be removed in Go 1.27 (per the Go 1.26 release notes).

## Goroutine Leak Profile (Go 1.26, Experimental)

Build with `GOEXPERIMENT=goroutineleakprofile` to enable. Adds a `goroutineleak` profile to `runtime/pprof` and a `/debug/pprof/goroutineleak` HTTP endpoint.

Uses GC reachability analysis: if a goroutine is blocked on a concurrency primitive (channel, mutex, cond) that is unreachable from any runnable goroutine, it is reported as leaked. Zero runtime overhead unless the profile is actively being collected. The Go team aims to enable goroutine leak profiles by default in Go 1.27 (per the Go 1.26 release notes).

This complements third-party leak detectors like `go.uber.org/goleak` and may replace them for some use cases once the feature stabilizes.

## Profiling Command Reference

### From benchmarks

```bash
# CPU + memory profiles
go test -run=^$ -bench=. -benchmem \
  -cpuprofile cpu.prof -memprofile mem.prof ./pkg
go tool pprof -http=:0 ./pkg.test cpu.prof

# Block + mutex contention
go test -run=^$ -bench=. \
  -blockprofile block.prof -mutexprofile mutex.prof ./pkg

# Execution trace
go test -run=^$ -bench=. -trace trace.out ./pkg
go tool trace trace.out
```

### From a running service

```bash
# CPU profile (30 seconds)
go tool pprof -http=:0 http://localhost:6060/debug/pprof/profile?seconds=30

# Heap profile (current allocations)
go tool pprof -http=:0 http://localhost:6060/debug/pprof/heap

# Goroutine dump
curl http://localhost:6060/debug/pprof/goroutine?debug=2

# Execution trace (5 seconds)
curl -o trace.out http://localhost:6060/debug/pprof/trace?seconds=5
go tool trace trace.out
```

### Heap profile modes

The heap profile has multiple views controlled by `-sample_index`:

| Mode | Shows |
|---|---|
| `inuse_space` (default) | Currently live memory |
| `inuse_objects` | Currently live object count |
| `alloc_space` | Total bytes allocated over time |
| `alloc_objects` | Total allocations over time |

Use `alloc_space` / `alloc_objects` to find allocation-heavy code paths even if objects are short-lived.

### Benchmark comparison workflow

```bash
# Capture baseline
go test -run=^$ -bench=. -benchmem -count=10 ./pkg > old.txt

# Make changes, then capture new results
go test -run=^$ -bench=. -benchmem -count=10 ./pkg > new.txt

# Compare with statistical analysis
benchstat old.txt new.txt
```

`benchstat` reports medians, confidence intervals, and highlights statistically significant changes. Use at least 10 runs (`-count=10`) to reduce noise.

## JSON Serialization Performance

`encoding/json` uses reflection on every call. In high-throughput paths, consider alternatives:

| Library | Approach | Notes |
|---|---|---|
| `encoding/json` | Reflection | Standard library; sufficient for most applications |
| `easyjson` | Code generation | Significantly faster; near-zero allocs |
| `sonic` | JIT + SIMD | Fastest in many benchmarks; platform-dependent |
| `go-json` | Code generation | Faster than stdlib; drop-in compatible API |

Go 1.25 includes an experimental `encoding/json/v2` (enable with `GOEXPERIMENT=jsonv2`) that may narrow this gap. Exact speedups vary by payload shape and size; always benchmark with your own data.

Always measure before switching. For most applications, `encoding/json` is fine. Only optimize when profiling shows JSON serialization is a bottleneck.
