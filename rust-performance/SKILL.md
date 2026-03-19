---
name: rust-performance
description: Guides Rust performance optimization including profiling, build configuration,
  allocation reduction, data structure selection, hot loop tuning, memory layout, and
  parallelism. Use when optimizing Rust code for speed or memory, choosing performance-oriented
  data structures, configuring release builds, profiling bottlenecks, or reviewing code
  for performance anti-patterns.
---

# Rust Performance

Practical guide for writing and reviewing high-performance Rust code. Covers Rust 2021+ edition. Check the project's `Cargo.toml` (`rust-version` field and `edition`) to determine the target Rust version and adjust advice accordingly.

The core principle: **measure first, optimize hot paths, validate every change**. Most large wins come from algorithm and data-structure changes, not micro-optimizations. Never optimize without profiling evidence.

## Performance Workflow

When optimizing Rust code, follow this sequence:

1. **Profile** -- Identify hot code with a sampling profiler (`samply`, `cargo flamegraph`, `perf`). Use DHAT or `dhat-rs` for allocation hotspots. Always profile release builds.
2. **Target** -- Focus on the top 1-3 bottlenecks. Most programs spend 80%+ of time in <20% of code.
3. **Hypothesize** -- Choose an optimization strategy based on the bottleneck type (CPU-bound, allocation-heavy, I/O-bound, cache-unfriendly).
4. **Benchmark** -- Write `criterion` benchmarks for the hot code path before changing anything. Establish a baseline.
5. **Optimize** -- Apply the smallest change that addresses the bottleneck. Use the guidance in this skill.
6. **Validate** -- Re-run benchmarks. If improvement is <5%, reconsider whether the change is worth the complexity.
7. **Re-profile** -- Confirm the bottleneck shifted. Repeat from step 1.

## Quick Impact Table

Optimizations ranked by effort-to-impact ratio. Try these first when profiling reveals a general bottleneck.

Actual impact is workload-dependent. The ranges below reflect community benchmarks and case studies but 0% improvement is common; always measure.

| Optimization | Effort | Reported Range | When to use |
|---|---|---|---|
| Switch global allocator (mimalloc/jemalloc) | 2 lines | 0-15% | Multi-threaded workloads, allocation-heavy code, musl targets |
| Enable LTO + `codegen-units = 1` | 3 lines Cargo.toml | 0-20% | Any release binary where build time is acceptable |
| `target-cpu=native` | 1 env var | Variable | Deployment builds where binary portability is not needed |
| Replace `HashMap` hasher | Drop-in type alias | 0-20% | Hashing is a profiled bottleneck; inputs are trusted |
| `Vec::with_capacity` / `reserve` | Trivial | Variable | Size is known or estimable; allocation profiler shows churn |
| Reuse collections with `.clear()` | Small refactor | Variable | Collections recreated in loops |
| `clone_from` instead of `= clone()` | Trivial | Variable | Cloning into existing capacity (Vec, String, HashMap) |
| Iterators instead of indexed access | Trivial | Variable | Hot loops with bounds-check overhead |

## Build Configuration

### Release Profile for Speed

```toml
[profile.release]
opt-level = 3          # Maximum optimization (default for release)
lto = "fat"            # Whole-program LTO; can significantly improve runtime (benchmark)
codegen-units = 1      # Single codegen unit; better optimization, slower compile
panic = "abort"        # Smaller binary, no unwind tables (disables catch_unwind)
strip = "symbols"      # Remove symbols; reduces binary size (incompatible with profiling)
```

**Note**: `strip = "symbols"` removes debug info and symbols needed by profilers and backtraces. Do not combine `strip` with the profiling-friendly settings below. Use a custom profile (see below) to avoid accidentally shipping one config when you need the other.

**LTO tiers** (lightest to heaviest):
- `lto = "off"` -- disables LTO entirely, including thin-local
- `lto = false` -- thin-local LTO only (default)
- `lto = "thin"` -- cross-crate thin LTO; good compile-time/runtime balance
- `lto = "fat"` (or `lto = true`) -- full whole-program LTO; maximum optimization, slowest compile

Validate with benchmarks; effects are workload-dependent.

### Profiling-Friendly Release Build

Use a custom profile that inherits from `release` to avoid config collisions between speed and profiling settings:

```toml
[profile.profiling]
inherits = "release"
debug = "line-tables-only"   # Minimal debug info for profiler stack traces
strip = "none"               # Preserve symbols for profiler output
```

```bash
RUSTFLAGS="-C force-frame-pointers=yes" cargo build --profile profiling
```

**Linux with lld/mold**: If flamegraph or perf stack traces look broken (addresses like `0xffffffffffffffff`), add `-C link-arg=-Wl,--no-rosegment`. The default `--rosegment` layout in lld/mold places `.eh_frame_hdr` and `.text` in separate ELF segments, which breaks perf's DWARF-based stack unwinding.

If profiler output shows mangled Rust symbols, prefer tools that demangle natively (Firefox Profiler, Hotspot) or post-process with `rustfilt`. Nightly toolchains default to v0 mangling since 2025-11-21; stable still defaults to legacy. Only adjust `-C symbol-mangling-version=v0` when you have a concrete tool compatibility problem.

### Target-Specific Tuning

```bash
RUSTFLAGS="-C target-cpu=native" cargo build --release
```

Enables CPU-specific instructions (AVX2, BMI2, etc.) available on the build machine. Do not use if binaries must run on other hardware. For portable deployment across a fleet with a known baseline, consider targeting a specific level (e.g., `-C target-cpu=x86-64-v3`) instead of `native`. The binary will still crash (SIGILL) on machines that don't support the targeted level.

### Profile-Guided Optimization (PGO)

PGO can yield significant improvement (10-20% reported in some workloads; less in others). The workflow: compile with `-Cprofile-generate`, run representative workloads to collect `.profraw` data, recompile with `-Cprofile-use`. The `cargo-pgo` crate automates this. Worth the effort for frequently deployed binaries (CLIs, servers).

## Profiling Tools

| Tool | Platform | Best for |
|---|---|---|
| `samply` | Linux, macOS, Windows | Sampling profiler; Firefox Profiler output; easiest to start with |
| `cargo flamegraph` | Linux, macOS, Windows | Flame graph visualization of CPU hotspots (uses `perf` on Linux, `xctrace` on macOS, `blondie` on Windows) |
| `perf` | Linux | Hardware counters, detailed CPU analysis; view with Hotspot |
| DHAT / `dhat-rs` | Linux (native) / all (crate) | Heap allocation profiling; identifies hot allocation sites and peak memory |
| `heaptrack` | Linux | Heap profiling with visualization |
| Cachegrind / Callgrind | Linux | Instruction counts, cache miss analysis |
| Coz (`coz-rs`) | Linux | Causal profiling -- identifies which functions matter for end-to-end improvement |

### Benchmarking

- **`criterion`** -- Standard micro-benchmarking library. Statistical analysis, outlier detection, comparison between runs.
- **`iai-callgrind`** -- Instruction-count-based benchmarks via Valgrind. Deterministic results suitable for CI where wall-clock benchmarks are noisy.

**Recommended flow**: Profile to find hotspots, write `criterion` benchmarks for hot paths, use `iai-callgrind` in CI for regression detection.

## Allocation & Memory

Allocation churn is the most common, most fixable performance bottleneck in Rust. Measure with DHAT before optimizing.

### Pre-Allocate When Size Is Known

```rust
let mut v = Vec::with_capacity(n);
for item in items {
    v.push(item);
}
```

Applies to `Vec`, `String`, `HashMap`, `HashSet`, and `VecDeque`. Use `reserve` or `reserve_exact` when the final size becomes known mid-function.

### Reuse Buffers

`Vec` never automatically shrinks. Clearing and refilling reuses the existing allocation:

```rust
buf.clear();       // retains capacity
buf.extend(data);  // no reallocation if data fits
```

Declare collections outside loops and `.clear()` between iterations. Pass `&mut Vec<T>` to functions instead of returning `Vec<T>` when the caller can provide a reusable buffer.

### Clone Efficiently

Use `a.clone_from(&b)` instead of `a = b.clone()`. `clone_from` reuses `a`'s existing allocation when the type supports it (`Vec`, `String`, `HashMap`, `Box<[T]>`).

### Avoid Unnecessary Allocations in Hot Paths

| Pattern | Allocates | Prefer |
|---|---|---|
| `format!("{}", x)` / `x.to_string()` | Always (new `String`) | `write!()` into reusable `String`, or `itoa`/`ryu` for numeric hot paths |
| `String::from` / `to_string` in loops | Per iteration | Reuse buffer with `.clear()` |
| `collect::<Vec<_>>()` mid-chain | Always | Chain more iterators, or `for_each()` |
| `BufRead::lines()` | New `String` per line | `read_line()` with reusable `String` |
| `Vec::new()` in hot loops | Per iteration | Declare outside loop, `.clear()` |

### Alternative Allocators

Switching the global allocator can improve performance without code changes:

- **mimalloc** -- Often fastest in benchmarks, especially multi-threaded and musl targets. Up to 11% throughput improvement in web API workloads.
- **jemalloc** -- Good for long-running servers. Enable transparent huge pages via `MALLOC_CONF` or `_RJEM_MALLOC_CONF` (tikv-jemallocator builds jemalloc with a `_rjem_` prefix by default, which changes the env var name).

**The default musl allocator can cause dramatic slowdowns** (up to 7x reported in some workloads). If targeting musl (Alpine, static binaries), benchmark with an alternative allocator early -- the difference can be significant but varies by workload.

Treat allocator changes as experiments -- benchmark before and after. See `references/reference.md` for setup code.

### Small-Buffer Optimization

For collections that are usually small, avoid heap allocation entirely:

| Crate | Type | Behavior |
|---|---|---|
| `smallvec` | `SmallVec<[T; N]>` | Inline up to N elements, then spills to heap |
| `arrayvec` | `ArrayVec<T, N>` | Fixed capacity, never heap-allocates, panics on overflow |
| `tinyvec` | `TinyVec<[T; N]>` | Like SmallVec but requires `T: Default`, no `unsafe` |
| `smartstring` | `SmartString` | Inline strings up to 23 bytes (64-bit) |
| `compact_str` | `CompactString` | Similar to smartstring; benchmarks slightly faster |

Use `SmallVec` for adjacency lists, small buffers, and collections where N covers >90% of cases.

## Data Structures

### HashMap Hasher Selection

The default `HashMap` uses SipHash 1-3 -- DoS-resistant but slow for small keys. If hashing is a profiled bottleneck and inputs are trusted:

| Hasher | Crate | Speed | Best for |
|---|---|---|---|
| FxHash | `rustc-hash` | Fastest | Integer keys, compiler internals |
| AHash | `ahash` | Very fast (uses AES-NI) | General trusted-input replacement |
| NoHash | `nohash-hasher` | Zero cost | Keys already well-distributed (random u64 IDs) |

For very small maps (<20 keys), `micromap` uses linear search and can outperform hash-based maps by avoiding hashing overhead.

**Always document the DoS tradeoff** when replacing the default hasher. Use the default for untrusted input.

### HashMap Iteration Cost

Iteration is **O(capacity)**, not O(len) -- empty buckets are visited. If you iterate frequently, avoid leaving capacity far above len. Use `shrink_to_fit()` after bulk removals if iteration performance matters.

### Ordered and Small-Key Maps

- **`BTreeMap` / `BTreeSet`** -- Ordered iteration; competitive when iteration dominates or keys are range-queried.
- **`Vec<(K,V)>` with linear scan** -- Often wins for very small maps (<10-20 entries) due to cache locality and branch prediction.
- **`IndexMap`** -- Deterministic insertion-order iteration with hash-based lookup.

### Enum and Niche Optimization

The Rust compiler uses invalid bit patterns to store enum discriminants without extra space. The following `Option<T>` niche optimizations are **guaranteed** by the language:

- `Option<&T>` / `Option<&mut T>` = pointer-sized (null represents `None`)
- `Option<Box<T>>` = pointer-sized (null represents `None`)
- `Option<NonZeroU32>` (and other `NonZero*` types) = same size as inner type (zero represents `None`)
- `Option<NonNull<T>>` = pointer-sized
- `Option<fn(...)>` (function pointers) = pointer-sized

Use `NonZero*` types when zero is not a valid value to get free `Option` wrapping. Use `bitflags` or `enumflags2` instead of `HashSet<EnumVariant>` for flag sets.

### Concurrent Maps

For read-heavy concurrent workloads, `DashMap` provides a sharded concurrent HashMap that avoids the coarse granularity of `RwLock<HashMap>`. For concurrent ordered access, `crossbeam-skiplist` provides lock-free ordered maps.

## Hot Loops & Codegen

### Bounds Check Elimination

Rust bounds-checks every index operation. In hot loops, prefer safe elimination techniques in this order:

1. **Use iterators** -- `for x in slice` has no bounds checks
2. **Use `chunks_exact()`** -- Tells the compiler the chunk size, enabling vectorization
3. **Slice once, index the sub-slice** -- Helps the optimizer reason about lengths
4. **Add assertions** -- `assert!(idx < slice.len())` before the loop lets the compiler elide checks inside
5. **Last resort: `get_unchecked()`** -- Requires explicit safety invariant comment and tests

### Inlining

- `#[inline]`, `#[inline(always)]`, `#[inline(never)]` are hints, not guarantees.
- Inlining is non-transitive -- if `f` calls `g`, both may need attributes.
- Re-measure after adding inline hints; inlining can unpredictably help or hurt.
- **Hot/cold split**: Mark hot functions `#[inline(always)]` and cold error paths `#[inline(never)]` or `#[cold]` to keep hot code tight.

```rust
#[inline(always)]
fn hot_path(data: &[u8]) -> u64 { /* fast path */ }

#[cold]
#[inline(never)]
fn handle_error(err: Error) { /* rare path */ }
```

### Machine Code Inspection

For very hot code, inspect generated assembly:
- **Compiler Explorer** (godbolt.org) for small snippets
- **`cargo-show-asm`** for full projects

Look for: removable bounds checks, missed vectorization, unexpected function calls in inner loops.

## Memory Layout & Cache

### Struct Layout

`repr(Rust)` (the default) allows the compiler to reorder fields, and rustc actively does so to reduce padding. However, the exact layout is unspecified and can change between compiler versions -- do not rely on any particular ordering for correctness. Use `repr(C)` only when C ABI compatibility is needed.

**Hot/cold field splitting**: Group frequently accessed fields together. Move rarely-used fields behind `Box` so hot data packs tightly into cache lines:

```rust
struct Particle {
    position: Vec3,    // hot: accessed every frame
    velocity: Vec3,    // hot: accessed every frame
    cold: Box<ParticleMetadata>,  // cold: accessed rarely
}
```

### Structure of Arrays (SoA)

When iterating over a single field across many items, SoA layout improves cache utilization and enables SIMD:

```rust
// AoS: iterating positions loads velocity/mass into cache too
struct Particle { position: Vec3, velocity: Vec3, mass: f32 }
let particles: Vec<Particle> = ...;

// SoA: iterating positions only loads positions
struct Particles {
    positions: Vec<Vec3>,
    velocities: Vec<Vec3>,
    masses: Vec<f32>,
}
```

SoA can substantially improve performance in data-intensive loops (reported 20-50% in some benchmarks, but highly workload-dependent). AoS is simpler and better when you access all fields together.

### False Sharing Prevention

In concurrent code, threads modifying adjacent data can invalidate each other's cache lines. Pad per-thread data to prevent false sharing. The effective padding needed differs from raw cache line sizes — for example, `CachePadded` uses 128 bytes on x86-64 because Intel's spatial prefetcher pulls pairs of 64-byte lines. Prefer `crossbeam_utils::CachePadded<T>` over hard-coding `#[repr(align(N))]`, as it encodes conservative per-architecture padding:

```rust
use crossbeam_utils::CachePadded;
use std::sync::atomic::AtomicU64;

struct PerThreadCounters {
    hits: CachePadded<AtomicU64>,
    misses: CachePadded<AtomicU64>,
}
```

### Wrapper Type Overhead

`RefCell` and `Mutex` add non-trivial access cost. If you usually access multiple wrapped values together, wrap them together:

```rust
// Instead of separate locks per field:
// x: Arc<Mutex<u32>>, y: Arc<Mutex<u32>>

// Coalesce into one lock:
xy: Arc<Mutex<(u32, u32)>>
```

Review red flag: many fine-grained `Arc<Mutex<_>>` fields in a hot path. Propose coalescing based on access patterns.

## Parallelism & Concurrency

### Rayon for CPU-Bound Work

Rayon parallelizes data-parallel workloads by changing `.iter()` to `.par_iter()`. Key considerations:

- Requires sufficient work per element (>1us per element or >1M elements) to offset overhead
- Use `sum`/`fold`/`reduce` patterns rather than shared mutable state
- Control thread count with a dedicated pool rather than `build_global()`, which can only be called once per process (subsequent calls return `Err`, causing panics if unwrapped -- a common footgun in libraries and tests):
  ```rust
  let pool = rayon::ThreadPoolBuilder::new().num_threads(n).build().unwrap();
  pool.install(|| {
      // parallel work uses this pool
  });
  ```
- Rayon defaults to logical core count. Whether physical-only is better depends on the workload -- memory-bandwidth-bound work may benefit from fewer threads, while compute-bound work with sufficient ILP can benefit from SMT. Benchmark to decide.

### Tokio: Don't Block the Executor

Blocking calls or heavy compute inside a future prevents the executor from driving other futures. Use `spawn_blocking` for blocking I/O.

**But**: `spawn_blocking` is not a CPU-parallelism engine. Its thread limit is very large by default. For CPU-bound work offloaded from async:
- Bound concurrency with a `Semaphore`
- Or use a dedicated Rayon pool

`spawn_blocking` tasks **cannot be aborted** once started. Dropping a Tokio runtime blocks indefinitely waiting for blocking tasks to complete. Use `shutdown_timeout` or `shutdown_background` to bound or skip that wait.

### Bounded Channels and Backpressure

Unbounded queues can consume all memory in long-running services. Always use bounded channels (`tokio::sync::mpsc::channel(cap)`, `crossbeam::channel::bounded(cap)`) and handle backpressure.

Review red flag: any producer/consumer pipeline with an unbounded queue in a long-running service.

### Async vs Threads Decision

| Workload | Use | Why |
|---|---|---|
| I/O-bound, many concurrent ops | Async (tokio) | Thousands of connections, minimal CPU per op |
| CPU-bound parallelism | Threads (Rayon) | Data-parallel computation across cores |
| Mixed | Tokio for I/O + `spawn_blocking`/Rayon for CPU | Never run CPU loops inside async tasks |

## Common Anti-Patterns

| Anti-pattern | Why it hurts | Fix |
|---|---|---|
| Benchmarking debug builds | 10-100x slower; results meaningless | Always `--release` |
| Unnecessary `.clone()` on `String`/`Vec` | Heap allocation per clone | Pass `&str`/`&[T]`, use `Cow`, or `Arc<str>` |
| `format!()` / `to_string()` in hot paths | Allocates a new `String` | `write!()` into reusable buffer, or `itoa`/`ryu` |
| `Box<dyn Trait>` in hot paths | Vtable indirection, prevents inlining | Generics, `impl Trait`, or enum dispatch |
| `collect()` mid-iterator-chain | Intermediate allocation | Chain more iterators |
| `Vec::new()` inside hot loops | Allocation per iteration | Declare outside, `.clear()` |
| `HashMap` with default hasher on int keys | SipHash overhead for trusted data | `FxHashMap` or `AHashMap` |
| `repr(packed)` for "performance" | Misaligned access, worse codegen | Only for FFI/on-disk formats |
| Inline hints without measurement | Can bloat code, hurt icache | Always benchmark before/after |
| Unbounded queues in servers | Memory exhaustion | Bounded channels + backpressure |
| Blocking sync I/O in async tasks | Starves the executor | `spawn_blocking`, async I/O, or dedicated runtime |

## Reference Files

| File | Contents | Load when |
|---|---|---|
| `references/reference.md` | Alternative allocator setup code, zero-copy patterns (bytes, mmap, serde, rkyv), SIMD and auto-vectorization guidance, string interning and arena allocators, compile-time computation (const fn, const generics, build scripts), detailed profiling setup, benchmarking framework examples, iterator performance patterns | Needing code examples, implementation patterns, zero-copy or SIMD guidance, allocator setup, or detailed tooling configuration for any topic above |
