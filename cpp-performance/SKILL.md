---
name: cpp-performance
description: Optimizes C++ for latency, throughput, memory footprint, cache behavior, allocations, contention, vectorization, and parallel scaling. Use when profiling, benchmarking, generating flame graphs, diagnosing false sharing or NUMA issues, tuning PGO/LTO/BOLT/AutoFDO builds, working with OpenMP/oneTBB/std::execution, or performing static performance review.
---

# C++ Performance

Use this skill when the task is to make C++ code faster, more scalable, or more memory-efficient. This includes hot paths, allocator churn, cache misses, false sharing, lock contention, parallelization, vectorization, build-flag tuning, and benchmark/profiler setup.

## Outcome

Aim to produce a result that is evidence-driven and easy to review:

1. Define the metric and workload.
2. Measure before changing code.
3. Identify the bottleneck with the right profiler or counters.
4. Make the smallest plausible change that moves that bottleneck.
5. Re-measure and explain the tradeoffs.
6. Preserve correctness, semantics, and maintainability.

## Default workflow

1. **Set the target**
   - Identify the primary metric: wall time, p50/p99 latency, throughput, CPU time, peak RSS, allocations/op, or scaling efficiency.
   - Identify the workload: production-like input, representative corpus, request mix, thread count, and problem size.
   - If the user did not provide this, infer a reasonable local workload and state the assumption.

2. **Build the right binary**
   - Prefer `RelWithDebInfo` or a `Release` build with debug info.
   - Keep optimization flags reproducible in the build system, not only in an ad hoc shell command.
   - For Linux `perf` call graphs, consider `-fno-omit-frame-pointer` if frame-pointer unwinding is desired.

3. **Establish a baseline**
   - Prefer an end-to-end benchmark for user-visible performance.
   - Use microbenchmarks only for isolated kernels, alternative implementations, container choices, or algorithmic subroutines.
   - Pin CPU cores and control NUMA placement when noise matters.
   - Use warmup and repetitions. Record compiler, flags, machine, input, and thread count.

4. **Find the real bottleneck**
   - First triage: on Intel/AMD, run `perf stat -M TopdownL1 -- ./binary` to classify cycles into Frontend Bound, Backend Bound (Memory vs Core), Bad Speculation, and Retiring. The dominant category points at the right reference file.
   - CPU hotspot: read `references/measurement-and-benchmarking.md` and `references/tool-recipes.md`
   - compiler/codegen issue (Frontend Bound, Bad Speculation): read `references/compiler-build-and-remarks.md`
   - memory footprint or allocation churn (Backend Bound — Memory): read `references/memory-layout-and-allocations.md`
   - poor scaling, contention, or false sharing: read `references/parallelism-and-contention.md`

5. **Choose the least invasive fix in this order**
   1. algorithm / data structure
   2. data layout / cache locality
   3. allocation behavior
   4. synchronization / contention
   5. parallel decomposition
   6. vectorization / instruction-level tuning
   7. build and link tuning (PGO/LTO/ThinLTO)

6. **Implement narrowly**
   - Change one or two high-confidence things first.
   - Avoid large speculative rewrites.
   - Prefer removing work over hiding work.
   - If the code cannot be run locally, do a static review and label recommendations as hypotheses.

7. **Validate**
   - Run tests.
   - Use sanitizers or static thread-safety analysis when correctness risk rises.
   - Re-benchmark after each material change.
   - If parallelized, measure the 1-thread baseline and the scaling curve, not only the best-case thread count.

8. **Present the result**
   - baseline
   - bottleneck
   - change
   - measured effect
   - tradeoffs / risks
   - next best step

## Rules that override instincts

- Do **not** claim a speedup without measurement.
- Do **not** default to `-Ofast`; preserve semantics unless relaxed math/FP behavior is explicitly acceptable.
- Do **not** assume more threads means more speed; prove the code is not already bandwidth-bound or contention-bound.
- Do **not** trust a microbenchmark until its data size, warmup, and setup cost are realistic.
- Do **not** use sanitizer timings as final performance numbers.
- Prefer existing project concurrency/runtime choices unless there is a measured reason to introduce a different one.

## Bottleneck playbook

### 1) Algorithm and data structure
Look for accidental `O(n^2)` work, repeated sorting, repeated parsing, and overly pointer-rich structures in hot paths.

High-value moves:
- flatten pointer-chasing structures into contiguous storage where practical
- use batched work instead of per-item overhead
- precompute or cache invariant work
- replace repeated lookups with direct indexing when ownership and lifecycle allow it

### 2) Cache locality and memory layout
Look for large hot structs, sparse field access, false sharing, and scattered reads.

High-value moves:
- keep hot fields together and move cold fields out of hot structs
- consider SoA instead of AoS when kernels touch only a subset of fields
- prefer indices into flat arrays over deep pointer graphs when it improves locality
- use `std::span` / `std::string_view` for non-owning views when it reduces copies and clarifies interfaces
- pad or align per-thread mutable state to avoid false sharing

### 3) Allocation behavior
Look for repeated small allocations, container growth in loops, and request-scoped temporary objects.

High-value moves:
- `reserve`, `resize`, and reuse storage
- hoist allocations out of hot loops
- batch or arena-allocate short-lived objects
- replace `std::unordered_map`/`std::unordered_set` (node-based, one allocation per insert) with `absl::flat_hash_map`, `boost::unordered_flat_map`, or `ankerl::unordered_dense::map` in hot paths
- consider `std::pmr::monotonic_buffer_resource` for phase-oriented temporary allocation (single-threaded; use `synchronized_pool_resource` across threads)
- only swap the global allocator (mimalloc, tcmalloc, jemalloc — typically via `LD_PRELOAD` first) when allocator contention or fragmentation is proven to matter

### 4) Synchronization and contention
Look for per-item atomics, global mutexes, and shared counters on hot lines.

High-value moves:
- sharding
- thread-local accumulation plus reduction
- batching shared writes
- separating frequently mutated fields from read-mostly fields
- replacing active polling or heavyweight wakeups with simpler wait/notify patterns when appropriate

### 5) Parallelism
Use the concurrency model already present in the codebase unless there is strong evidence to change it.

Choose among these patterns:
- **`std::execution`** (C++17 `seq`/`par`/`par_unseq`; C++20 added `unseq`) for straightforward data-parallel algorithms
- **OpenMP** for regular loop nests and reductions
- **oneTBB** for task decomposition, blocked ranges, pipelines, and work-stealing

Parallelization checklist:
- confirm each worker has enough work to amortize scheduling cost
- minimize shared writes
- verify the loop body is safe for the chosen execution model
- measure scaling across several thread counts
- inspect NUMA locality on multisocket machines

### 6) Compiler and codegen
Use compiler remarks to learn whether inlining, vectorization, or unrolling was applied or missed.

High-value moves:
- remove aliasing ambiguity (`__restrict__` on hot pointer parameters when `const` and `std::span` are not enough)
- make loop trip counts and data dependencies clearer
- hoist invariant work
- simplify unpredictable branches; reach for C++20 `[[likely]]`/`[[unlikely]]` only when profiling shows a >95% biased branch in a hot block (they affect block layout more than predictor state on modern OoO cores)
- inspect assembly only after the profiler points to a tiny hot kernel; Compiler Explorer (godbolt.org) is the standard scratchpad for codegen iteration

## Output template

Use this structure when reporting work:

```text
Goal:
Workload / assumptions:
Baseline:
Observed bottleneck:
Change(s):
Result:
Correctness checks:
Tradeoffs / caveats:
Next best step:
```

If results are unmeasured, explicitly label them as **hypotheses**.

## Gotchas

- `perf` is primarily a Linux workflow. If unavailable, use the nearest profiler available in the environment, but keep the same measure → change → remeasure loop.
- `perf record --call-graph fp` needs reliable frame pointers. Upstream GCC/Clang still default to `-fomit-frame-pointer` at `-O1+` on x86-64; only Fedora 38+ and Ubuntu 24.04+ build *distro packages* with frame pointers. User builds still need explicit `-fno-omit-frame-pointer`. Otherwise prefer DWARF or LBR when supported.
- `std::execution::par_unseq` / `unseq` require vectorization-safe bodies: no mutex acquisition, no non-lockfree atomics, and no calls to standard-library functions that synchronize with other invocations. Memory allocation (`new`/`delete`, `malloc`/`free`) is explicitly permitted — the standard carves allocation/deallocation out of the "vectorization-unsafe" definition. Calling a truly forbidden operation is undefined behavior, not a compile error.
- `std::pmr::monotonic_buffer_resource` is **not thread-safe**. Use `synchronized_pool_resource` for multi-threaded callers.
- `std::hardware_destructive_interference_size` is not ABI-stable. GCC issues `-Winterference-size` if used in a header that crosses TU boundaries. Either hard-code 64 (or 128 for Apple Silicon / Intel adjacent-line prefetch) inside an internal-only TU, or guard with `#ifdef __cpp_lib_hardware_interference_size`.
- `kernel.perf_event_paranoid=2` (the distro default) is enough for sample-based user-space profiling. PMU event reads (`cycles`, `instructions`) need `=1`; kernel profiling needs `=0` or `-1`.
- Thermal throttling silently ruins benchmarks. Pin governor with `cpupower frequency-set -g performance` and watch `turbostat --interval 1` for `PkgWatt` / `Avg_MHz` excursions during runs.
- NUMA effects can dominate multisocket scaling. Inspect topology with `numactl --hardware` or `lstopo`.
- Cachegrind/Callgrind are slow but useful when hardware counters are unavailable or noisy.
- More aggressive math flags (`-Ofast`, `-ffast-math`) can change numerical behavior. Treat them as semantics changes.
- Sanitizer-instrumented binaries are correctness tools, not performance baselines.

## Supporting files

Load only the files relevant to the current bottleneck:

- [references/measurement-and-benchmarking.md](references/measurement-and-benchmarking.md) — baseline design, benchmark hygiene, Google Benchmark, `perf stat`, TMA top-down, hyperfine, pinning, NUMA, thermal throttling
- [references/compiler-build-and-remarks.md](references/compiler-build-and-remarks.md) — CMake build modes, Clang/GCC optimization remarks, instrumented PGO, AutoFDO/CSSPGO, LTO/ThinLTO, BOLT, function multi-versioning
- [references/memory-layout-and-allocations.md](references/memory-layout-and-allocations.md) — locality, `std::pmr`, `std::span`, false sharing, allocator alternatives (mimalloc/tcmalloc/jemalloc), flat hash maps, THP, `std::vector<bool>` trap
- [references/parallelism-and-contention.md](references/parallelism-and-contention.md) — OpenMP, oneTBB, `std::execution`, contention reduction, NUMA tooling, race-checking
- [references/tool-recipes.md](references/tool-recipes.md) — copy-paste workflows for `perf`, `perf c2c`, `perf mem`, FlameGraph, Valgrind tools, Heaptrack, hyperfine, bloaty, BOLT, `llvm-mca`, coz
- [references/review-checklist.md](references/review-checklist.md) — static review rubric for code that cannot be run locally
- [references/source-index.md](references/source-index.md) — curated primary sources behind this skill

## Bundled scripts

These helper scripts are optional. They standardize common workflows and reduce repetitive shell setup.

- `scripts/check-tools.sh`
- `scripts/run-google-benchmark.sh`
- `scripts/run-perf-stat.sh`
- `scripts/run-perf-record.sh`
- `scripts/collect-compiler-remarks.sh`
