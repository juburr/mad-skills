# Memory layout and allocations

## Start with locality, not syntax

Many C++ performance problems are really memory-movement problems:

- too many cache lines touched per operation
- too many allocations
- pointer-heavy traversal
- false sharing between threads
- oversized hot structs
- temporary allocations that should never have existed

When runtime is dominated by memory stalls, reducing instruction count may not help much unless you also reduce memory traffic.

## Data layout heuristics

### Hot vs cold fields
Keep frequently read fields close together.
Move infrequently used or bulky fields out of hot structs.

Typical split:
- hot path fields in a compact header
- cold metadata in a side structure or secondary lookup table

### Indices instead of pointers
When ownership permits, replace deep pointer graphs with integer indices into contiguous arrays or vectors.

Benefits:
- smaller references
- denser storage
- better prefetchability
- often fewer allocations

### SoA vs AoS
If a loop touches only a subset of fields, structure-of-arrays can reduce wasted bandwidth.

Prefer SoA when:
- kernels scan one or two fields across many objects
- vectorization matters
- cache footprint is limiting speed

Prefer AoS when:
- code frequently needs most fields together
- object-level locality matters more than field-level scans

## Non-owning views

### `std::span`
Use `std::span<T>` to express a non-owning contiguous range.
It often removes the need to copy or materialize temporary vectors just to pass size + pointer together.

### `std::string_view`
Use `std::string_view` for read-only string-like inputs when ownership does not need to transfer.

Caveats:
- it is non-owning; lifetime bugs are easy to introduce
- it is not guaranteed to be null-terminated
- if you construct from `const char*` without a size, a length scan may be needed; if you already know the size, pass it

## Allocation reduction

Look for these first:
- `std::vector` growth without `reserve`
- `std::string` concatenation or formatting in hot loops
- per-item heap allocation for small objects
- temporary containers created and destroyed every call
- repeated conversion to owning strings or buffers

Useful patterns:
- reserve once, reuse often
- use scratch buffers
- move allocations out of the critical branch
- reuse arena-style storage for short-lived objects
- batch objects into contiguous storage instead of allocating each separately

## `std::pmr::monotonic_buffer_resource`

Good fit when allocation is phase-oriented:

- parse a request
- build transient objects
- process them
- free everything together

Pros:
- very fast allocations
- simple lifetime model
- geometric upstream growth

Cons:
- memory is released only when the resource is destroyed
- not thread-safe
- poor fit when you need fine-grained deallocation

Typical pattern:
```cpp
std::byte buffer[1 << 16];
std::pmr::monotonic_buffer_resource pool(buffer, sizeof(buffer));
std::pmr::vector<Token> tokens{&pool};
```

## False sharing

False sharing happens when different threads write to different data that lives on the same cache line.

Symptoms:
- poor scaling despite low algorithmic complexity
- high coherence traffic
- performance gets worse with more threads
- small shared structs with per-thread counters packed together

Detect with `perf c2c record/report` (see `tool-recipes.md`) — it identifies the exact cache lines and offsets where HITM events cluster.

Mitigations:
- separate per-thread mutable state onto different cache lines
- use `alignas` or padding carefully
- place read-mostly fields away from frequently mutated fields
- keep thread-local state truly thread-local

### `std::hardware_destructive_interference_size` is not ABI-stable

C++17 added `std::hardware_destructive_interference_size`, but using it casually creates an ABI hazard: the value depends on `-mtune` and varies across platforms (libstdc++ uses 64 on x86-64, but Apple Silicon and some Intel adjacent-line prefetchers want 128). GCC emits `-Winterference-size` (on with `-Wall`/`-Wextra`) when you use it in a declaration that crosses TU boundaries.

Safe patterns:

```cpp
// OK: internal-only, never appears in a public header
namespace {
  inline constexpr std::size_t kCacheLine = 64;  // x86-64 / aarch64; bump to 128 for Apple Silicon
}

// OK: guard public uses behind a feature test, accept that ABI can shift
#ifdef __cpp_lib_hardware_interference_size
  inline constexpr std::size_t kCacheLine = std::hardware_destructive_interference_size;
#else
  inline constexpr std::size_t kCacheLine = 64;
#endif

struct alignas(kCacheLine) PerThreadCounters {
  std::atomic<std::uint64_t> hits{0};
  std::atomic<std::uint64_t> misses{0};
};
```

For library APIs, hard-code the constant inside an unexported TU rather than baking the standard's value into your public ABI.

## Allocator scalability

If profiling shows the global allocator is contended in multithreaded code:
- first reduce the number of allocations
- then consider an allocator designed for concurrency

oneTBB provides:
- `scalable_allocator<T>` for allocator scalability bottlenecks
- `cache_aligned_allocator<T>` when alignment and interference matter

Do not change allocators blindly. If allocation volume is the real problem, a faster allocator may only mask it.

### Process-wide allocator replacement

When the bottleneck is glibc `malloc` contention or fragmentation under high allocation rates, swapping the global allocator is often a 5–30% win with zero code changes. Test via `LD_PRELOAD` first, then bake into the build if it sticks.

| Allocator | Strengths | Notes |
|---|---|---|
| **mimalloc** (Microsoft) | Fast small-allocation path; low fragmentation; transparent huge page support | Often wins on small-allocation-heavy workloads. `LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libmimalloc.so.2` |
| **tcmalloc** (gperftools / google/tcmalloc) | Strong throughput; large-allocation friendly; integrates with gperftools heap profiler | Two flavors exist — gperftools tcmalloc (older, packaged in distros) and google/tcmalloc (newer, requires Bazel/Abseil) |
| **jemalloc** | Excellent multi-arena scaling; low tail latency on long-running servers; mature MALLCTL knobs and built-in profiling | The default for many databases (Redis, Aerospike, Cassandra historically). `MALLOC_CONF=background_thread:true,metadata_thp:auto` is a common starting tune |

A faster allocator does not fix excessive allocation volume — it only masks it. Reduce allocation rate first; swap the allocator second.

## Hash maps: avoid `std::unordered_map` in hot paths

`std::unordered_map` is required by the standard to be node-based with stable references, which forces a heap allocation per insert and pointer-chasing iteration. On modern hardware, open-addressed flat hash tables are typically 2–5× faster:

| Container | Source | When to use |
|---|---|---|
| `absl::flat_hash_map` / `absl::flat_hash_set` | Abseil | General drop-in replacement; SwissTable design; values are not pointer-stable |
| `boost::unordered_flat_map` | Boost.Unordered (1.81+) | Same niche as absl; available without an Abseil dependency |
| `ankerl::unordered_dense::map` | header-only (martinus/unordered_dense) | Fastest in many benchmarks; values stored in a contiguous vector |
| `tsl::robin_map` / `tsl::hopscotch_map` | header-only (Tessil) | Good when iteration order or load-factor tuning matters |

Reach for the node-based `std::unordered_map` only when callers actually depend on reference stability across rehashes.

## `std::vector<bool>` is not a vector of `bool`

`std::vector<bool>` is a specialization that packs bits, which means `operator[]` returns a proxy and you cannot take a `bool*` to its data. It is a frequent source of subtle aliasing and performance bugs in templated code. Prefer:

- `std::vector<char>` or `std::vector<std::uint8_t>` when you want a real contiguous array of byte-sized booleans
- `std::bitset<N>` when the size is known at compile time
- `boost::dynamic_bitset` when you want runtime-sized packed bits with bulk bitwise ops

## Transparent Huge Pages and TLB pressure

Working sets larger than a few hundred MB often spend significant time in dTLB misses. Two levers:

1. **Transparent Huge Pages (THP)** — kernel-managed 2 MB pages, enabled per system at `/sys/kernel/mm/transparent_hugepage/enabled`. The `madvise` mode is the safest default.
2. **`madvise(MADV_HUGEPAGE)` on hot regions** — request huge-page promotion explicitly for large mappings (arenas, mmapped files, custom heaps).

Watch out: THP can cause latency spikes for some database workloads (compaction stalls). Measure both `dTLB-load-misses` and tail latency before and after.

## Heap profiling tool choices

### Heaptrack
Use when you want:
- allocation hotspots
- temporary allocation patterns
- memory footprint over time
- stack traces attached to allocations

### Massif
Use when you want:
- peak heap analysis
- comparative runs
- a conservative, reproducible heap profile

### DHAT
Use when you want:
- allocation lifetimes
- read/write patterns
- underused allocations
- churn and transient allocation diagnosis

## Static review triggers

When reading code without running it, flag:
- node-based containers in hot paths
- per-message or per-record heap allocation
- implicit string ownership changes
- APIs that copy buffers when a view would work
- giant structs passed through multiple layers when only one field is used
- thread-local counters stored inside one shared array without padding
