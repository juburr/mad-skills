# Parallelism and contention

## Decide whether to parallelize at all

Parallelism helps only when:
- there is enough independent work
- scheduling overhead is small relative to task cost
- memory bandwidth is not already saturated
- shared writes are limited
- the data layout does not force heavy coherence traffic

Before parallelizing, measure the 1-thread baseline.

## `std::execution`

Use parallel algorithms when the problem already matches the algorithm library well.

- `std::execution::seq` (C++17): sequential
- `std::execution::par` (C++17): parallel execution is permitted
- `std::execution::par_unseq` (C++17): may be parallel **and** vectorized; bodies must be vectorization-safe
- `std::execution::unseq` (**C++20**, not C++17): may be vectorized but not parallelized

`par_unseq` and `unseq` forbid synchronization primitives in the loop body: mutex lock/unlock, non-lockfree `std::atomic` operations, and standard-library functions that synchronize with other invocations. The normative definition of "vectorization-unsafe" — including its explicit carve-out for memory allocation and deallocation — is C++17 [algorithms.parallel.defns] verbatim (adopted from the Parallelism TS via P0024; P1001R2 only added `unsequenced_policy`/`unseq` in C++20). So `new`, `delete`, `malloc`, `free`, and `std::allocator::allocate` are **allowed**, even though some secondary docs incorrectly list them. The further carve-out for lock-free atomic read-modify-write operations is a current-working-draft (C++26-era) change — under a strict C++17/20 reading even lock-free synchronizing atomics are not formally exempt, though implementations tolerate them. Calling a truly forbidden operation is **undefined behavior**, not a compile error.

Good fits:
- map/filter/reduce style operations
- transforms on contiguous ranges
- sort/reduce where the implementation support is known and adequate

Bad fits:
- loop bodies with locks or synchronizing atomics
- code with hidden global state
- irregular work with heavy per-item skew
- tasks needing complex orchestration

When in doubt, start with `par`, not `par_unseq`.

### Which implementations actually parallelize

- **libstdc++** dispatches parallel policies to oneTBB — without TBB available at build time and linked (`-ltbb`), parallel policies compile but run serially
- **libc++** ships parallel algorithms only as experimental
- **MSVC** parallelizes `par` but treats `par_unseq` like `par` (no vectorized execution)

Always benchmark to confirm parallel execution actually happened.

## OpenMP

OpenMP is a strong choice for regular loop nests, reductions, and places where you want a lightweight, explicit loop-parallel annotation strategy.

Good fits:
- numeric kernels
- stencil or image-style loops
- reductions
- loops over dense arrays

Things to check:
- static vs dynamic schedule
- chunk size
- reduction correctness
- oversubscription
- thread affinity and NUMA

Do not add OpenMP directives to a loop with heavy allocator traffic or shared writes and expect magic speedups.

## oneTBB

oneTBB is a strong choice for:
- task decomposition
- work-stealing
- blocked ranges
- irregular parallelism
- pipelines and flow graphs

`parallel_for` is a good default when the iteration space is regular, but remember:
- there is no guarantee every iteration actually runs in parallel
- deadlock is possible if earlier iterations wait for later ones
- the default partitioning strategy is `auto_partitioner`

oneTBB also provides allocator tools that can help when parallel scalability is limited by memory allocation.

## Contention reduction patterns

### Thread-local accumulation + reduction
Replace:
- per-item global atomic increments
- per-item locking for shared counters

With:
- thread-local partial results
- one merge/reduction phase

### Relaxed ordering for statistics counters
Statistics counters should use `fetch_add(1, std::memory_order_relaxed)` — the default `seq_cst` RMW adds ordering cost the counter does not need. But relaxed ordering does not fix contention itself: the cache line still bounces between cores. Sharding or thread-local accumulation does.

### Sharding
Split a shared structure into multiple independent shards keyed by hash, range, or NUMA node.

Good for:
- maps
- queues
- caches
- counters

### Batch publication
If many small updates hit shared state, batch them and publish less often.

### Read-mostly / write-hot separation
Separate the data that all threads read from the data that a few threads mutate frequently.

## NUMA topology and placement

On multi-socket and large single-socket-with-CCDs systems, remote memory access can dominate scaling beyond a single node. Always inspect topology before drawing conclusions about scaling — see `tool-recipes.md` for the `numactl` / `lstopo` / `numastat` commands.

Patterns that help:
- pin worker threads to a single node when the data set fits
- allocate per-NUMA-node arenas and route work by node
- shard hot read/write structures by node, not just by thread
- prefer first-touch allocation: have the thread that will use a page touch it first so it lands on the right node

If `perf c2c` shows HITM events crossing nodes, you have remote-memory contention, not just false sharing.

## Race detection and correctness tools

Use these when parallel changes are non-trivial:

- **ThreadSanitizer** for runtime race detection
- **Clang thread-safety analysis** (`-Wthread-safety`) for annotated, compile-time locking checks

Remember:
- ThreadSanitizer is intentionally expensive and changes timing substantially
- a “fast” parallel implementation that is racy is not an optimization

## `atomic::wait` / `notify`

For simple state-change coordination, C++20 atomic wait/notify can be a cleaner alternative than active spinning or heavier synchronization patterns.

Use it when:
- a thread waits for a scalar state to change
- the wakeup condition is simple
- the design benefits from keeping the synchronization tied to one atomic value

Do not use it as a default replacement for every condition-variable pattern. Simplicity of the state machine matters more than novelty.

## Scaling checklist

When reporting parallel results, include:

- thread counts tested
- 1-thread baseline
- best speedup
- where scaling flattened or regressed
- likely limit: synchronization, false sharing, NUMA, or bandwidth

A good result description sounds like this:

> 1-thread baseline: 180 ms. Best result: 78 ms at 4 threads (2.3x). No further gain at 8 threads; perf counters and topology suggest memory bandwidth saturation and some remaining false sharing in per-thread statistics.
