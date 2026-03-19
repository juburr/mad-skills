---
name: go-performance
description: Guides writing high-performance Go code and conducting performance-focused code reviews. Use when optimizing Go services for throughput or latency, diagnosing performance regressions, tuning GC or runtime settings, or reviewing Go code for performance pitfalls.
---

# Go Performance

Helps write high-throughput, low-latency Go code and review existing code for performance risks across five dimensions: CPU time, allocation rate / GC cost, memory footprint, contention, and I/O overhead.

## Measurement-First Workflow

Never optimize without a measured bottleneck. Follow this loop:

1. **Establish a baseline** - benchmark the current code with allocation stats.
2. **Classify the bottleneck** - CPU? allocations/GC? contention? I/O?
3. **Profile** - select the right profiling tool for the bottleneck class.
4. **Apply a targeted fix** - change one thing at a time.
5. **Re-benchmark and compare** - use `benchstat` to confirm statistical improvement.

| Bottleneck | Primary tool | Secondary tool |
|---|---|---|
| CPU time | CPU pprof | execution trace |
| Allocation rate / GC | heap pprof, `-benchmem` | compiler escape analysis (`-m`) |
| Memory footprint | heap pprof (`inuse_space`) | `runtime/metrics` |
| Lock contention | mutex pprof | block pprof |
| I/O / scheduling | execution trace | fgprof (off-CPU) |

## Benchmarking

### Writing benchmarks

Use `testing.B.Loop()` (Go 1.24+) instead of the traditional `for i := 0; i < b.N; i++` pattern. It prevents compiler dead-code elimination of the benchmark body and avoids running setup code per-iteration:

```go
func BenchmarkFoo(b *testing.B) {
    input := makeInput() // setup runs once
    b.ReportAllocs()
    b.ResetTimer()
    for b.Loop() {
        _ = Foo(input)
    }
}
```

### Running benchmarks

```bash
# Run with allocation stats, 10 repetitions for statistical validity
go test -bench=BenchmarkFoo -benchmem -count=10 ./pkg

# Compare before/after
benchstat before.txt after.txt
```

Use `-count=10` or more for `benchstat` to compute meaningful confidence intervals.

## Profiling

### CPU and memory profiles from benchmarks

```bash
go test -run=^$ -bench=BenchmarkFoo -benchmem \
  -cpuprofile cpu.prof -memprofile mem.prof ./pkg
go tool pprof -http=:0 ./pkg.test cpu.prof
```

### Contention profiles from benchmarks

```bash
go test -run=^$ -bench=BenchmarkFoo \
  -blockprofile block.prof -mutexprofile mutex.prof ./pkg
```

Block and mutex profiles are not enabled by default in production. Enable via `runtime.SetBlockProfileRate` and `runtime.SetMutexProfileFraction`.

### Production profiling with net/http/pprof

```go
import _ "net/http/pprof"

go func() {
    log.Println(http.ListenAndServe("localhost:6060", nil))
}()
```

Bind to localhost or an admin port. Pprof endpoints are sensitive and must not be exposed to untrusted networks. As of Go 1.22, all pprof endpoints require GET requests.

### Execution tracing

Use tracing to diagnose latency, scheduling, and GC timing issues that CPU profiles miss:

```bash
go test -trace trace.out ./pkg
go tool trace trace.out
```

Go 1.25 adds `runtime/trace.FlightRecorder` for lightweight continuous trace capture with on-demand snapshots around slow events.

### Off-CPU profiling with fgprof

Go's built-in CPU profiler only captures on-CPU time. Use `github.com/felixge/fgprof` to capture both on-CPU and off-CPU time (I/O waits, lock contention, sleep) in a single profile.

## Compiler Diagnostics

### Escape analysis

```bash
go build -gcflags="-m" ./pkg       # basic escape decisions
go build -gcflags="-m=2" ./pkg     # detailed escape reasoning
```

### Bounds check elimination

```bash
go build -gcflags="-d=ssa/check_bce/debug=1" ./pkg
```

### Assembly output

```bash
go build -gcflags="-S" ./pkg
```

gopls also surfaces escape, inlining, and bounds check diagnostics inline in editors that support it.

## Code Review Checklists

### CPU hot path

| Signal | Risk | Action |
|---|---|---|
| `fmt.Sprintf` / `fmt.Fprintf` in hot loop | Format parsing + interface boxing per call | Use `strconv` or `strings.Builder` |
| Reflection (`reflect.*`) in hot path | Orders of magnitude slower than static dispatch | Cache reflected types at init, use type switches, or code-generate |
| Interface method calls in tight loop | Prevents inlining; measurably slower | Use concrete types; PGO can devirtualize |
| Bounds checks in tight loop | Branch per access | Hoist a single bounds check before the loop body |
| `defer` in tiny hot function | Adds inlining cost | Move defer to caller or remove if not needed |

### Allocations and memory

| Signal | Risk | Action |
|---|---|---|
| `s += ...` in loop | Quadratic growth, allocation per iteration | Use `strings.Builder` with `Grow()` |
| `append` without capacity hint | Repeated growth and copy | `make([]T, 0, expectedSize)` |
| `make(map[K]V)` without size hint | Rehash/growth overhead | `make(map[K]V, expectedSize)` |
| Returning `*T` from hot function | Forces local to escape to heap | Return `T` by value when practical |
| Closure capturing loop variable | Closure allocated per iteration | Pass as function parameter |
| Storing large values behind `interface{}` | Forces heap boxing | Use concrete types on hot paths |
| Small subslice of large `[]byte` | Retains entire backing array | Copy to a new, right-sized slice |
| Per-request buffer/encoder creation | Allocation per request | Pool with `sync.Pool`; reset before `Put()` |
| `encoding/json` in high-throughput path | Heavy reflection per call | Measure; consider code-gen alternatives |

### Concurrency and contention

| Signal | Risk | Action |
|---|---|---|
| Unbounded goroutine creation | Memory exhaustion, downstream overload | Use worker pool with bounded concurrency |
| Missing context cancellation | Goroutine leak (2-8KB stack each) | Always propagate and check `ctx.Done()` |
| Hot mutex on fast path | Serializes all goroutines | Shard data, use atomics, or reduce critical section |
| Channel used as lock | Higher overhead than `sync.Mutex` | Use `sync.Mutex` for mutual exclusion |
| `sync.RWMutex` under extreme read contention | Atomic overhead on reader count | Shard by goroutine/key |

### Data structures

| Signal | Risk | Action |
|---|---|---|
| Struct fields ordered randomly | Padding wastes memory | Order fields largest-to-smallest alignment |
| Concurrent writes to adjacent struct fields | False sharing across cache lines | Pad with `cpu.CacheLinePad` from `golang.org/x/sys/cpu` |
| Small sorted collection using map | Cache-unfriendly | Sorted slice + binary search for <50 elements |
| `string([]byte)` in hot path | Allocates and copies | Use `unsafe.String` carefully, or restructure to avoid conversion |

## Runtime Tuning

### GC: GOGC and GOMEMLIMIT

`GOGC` (default 100) controls GC frequency. Higher values reduce GC CPU cost but increase memory use.

`GOMEMLIMIT` (Go 1.19+) sets a soft memory limit on Go runtime memory. The GC becomes more aggressive as usage approaches the limit.

| Environment | Recommended setting |
|---|---|
| Container with fixed memory | `GOMEMLIMIT=<90% of container limit>`, keep `GOGC=100` |
| Container, minimize GC CPU | `GOGC=off`, `GOMEMLIMIT=<90% of container limit>` |
| Batch / CLI tool | Usually defaults are fine |

The ballast technique (`var _ = make([]byte, 1<<30)`) is obsolete. Use `GOMEMLIMIT` instead.

Use `GODEBUG=gctrace=1` to print GC diagnostics to stderr.

### GOMAXPROCS

Go 1.25+ auto-detects container CPU limits (cgroups). Explicitly setting `GOMAXPROCS` disables auto-adjustment. Third-party libraries like `automaxprocs` are no longer needed on Go 1.25+.

Container-aware defaults are gated by the `go` directive in `go.mod`. A module with `go 1.24` will not get the new defaults even when built with Go 1.25+. Set `go 1.25.0` or later in `go.mod` to opt in.

To disable container-aware defaults for troubleshooting:

```bash
GODEBUG=containermaxprocs=0,updatemaxprocs=0 ./myapp
```

Verify the effective value at runtime with `runtime.GOMAXPROCS(0)`.

### Profile-Guided Optimization (PGO)

PGO improves performance 2-14% by feeding production CPU profiles back to the compiler.

1. Collect a CPU profile under representative load.
2. Save as `default.pgo` in the main package directory.
3. Rebuild. The compiler uses it automatically.

PGO enables more aggressive inlining of hot functions and devirtualization of interface calls.

## Recent Go Performance Features

| Version | Feature | Impact |
|---|---|---|
| Go 1.21 | PGO GA | 2-14% improvement from production profiles |
| Go 1.23 | `unique` package | String interning with GC-aware cleanup; pointer-fast equality |
| Go 1.24 | Swiss Tables maps | Significantly faster map ops and lower memory in microbenchmarks |
| Go 1.24 | `sync.Map` rewrite | Disjoint key modifications contend far less |
| Go 1.24 | `weak.Pointer[T]` | Weak references for caches; GC-friendly |
| Go 1.24 | `runtime.AddCleanup` | Replaces `SetFinalizer`; faster, handles cycles |
| Go 1.24 | `testing.B.Loop()` | Correct benchmark iteration; prevents dead-code elimination |
| Go 1.25 | Container-aware GOMAXPROCS | Auto-detects cgroup CPU limits |
| Go 1.25 | Flight recorder | Continuous trace capture with on-demand snapshots |
| Go 1.25 | Green Tea GC (experimental) | Reduced GC overhead; scans memory in 8 KiB spans |
| Go 1.26 | Green Tea GC (default) | Now enabled by default; opt-out via `GOEXPERIMENT=nogreenteagc` |
| Go 1.26 | ~30% faster cgo calls | Reduced baseline cgo overhead; no code changes needed |
| Go 1.26 | Goroutine leak profile (experimental) | `GOEXPERIMENT=goroutineleakprofile`; zero overhead when not collecting |
| Go 1.26 | `testing.B.Loop()` inlining fix | Loop bodies now properly inlined; fixes unexpected allocations |

For detailed code examples, version-specific patterns, and deeper explanations of each topic, read `references/reference.md`.

## Reference Files

| File | Contents | Load when |
|---|---|---|
| `references/reference.md` | Detailed code patterns for allocation optimization, struct layout, HTTP client tuning, GC configuration, PGO workflow, sync.Pool usage, and Go version-specific features | Needing implementation examples, quantitative guidance, or version-specific details beyond the checklists above |
