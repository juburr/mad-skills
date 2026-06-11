---
name: cpp-performance
description: Guides C++ performance optimization including profiling, benchmarking, memory layout, allocation reduction, parallelism, vectorization, and build tuning (PGO/LTO/BOLT). Use when optimizing C++ code for speed or memory, diagnosing performance regressions, profiling or benchmarking C++ programs, generating flame graphs, fixing false sharing or NUMA scaling issues, working with OpenMP/oneTBB/std::execution, or reviewing C++ code for performance anti-patterns.
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
   - First triage: classify pipeline slots with top-down analysis — Intel: `perf stat -M TopdownL1 -- ./binary`; AMD Zen 4+: `perf stat -M PipelineL1 -- ./binary`. Level 1 has four buckets: Frontend Bound, Bad Speculation, Backend Bound, Retiring; level 2 (`-M TopdownL2` / `-M PipelineL2`) splits Backend Bound into Memory vs Core. The dominant category points at the right reference file.
   - CPU hotspot: read `references/measurement-and-benchmarking.md` and `references/tool-recipes.md`
   - compiler/codegen issue (Frontend Bound, Bad Speculation): read `references/compiler-build-and-remarks.md`
   - memory footprint or allocation churn (Backend Bound → Memory at level 2): read `references/memory-layout-and-allocations.md`
   - poor scaling, contention, or false sharing: read `references/parallelism-and-contention.md`
   - source-level review without running the code: read `references/cpp-language-patterns.md` and `references/review-checklist.md`

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
- **`std::execution`** (C++17 `seq`/`par`/`par_unseq`; C++20 added `unseq`) for straightforward data-parallel algorithms — but verify the library actually parallelizes: libstdc++ needs the TBB backend or it runs serially, and MSVC treats `par_unseq` as `par` (see `references/parallelism-and-contention.md`)
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

- `perf` is primarily a Linux workflow. On macOS or Windows, map the same measure → change → remeasure loop onto the native tools (see `references/tool-recipes.md` § Non-Linux platforms).
- `perf record --call-graph fp` needs reliable frame pointers. GCC/Clang enable `-fomit-frame-pointer` at `-O1+` on x86-64, and only some distros (Fedora 38+, Ubuntu 24.04+, Arch) build packages with frame pointers — verify on the target rather than assume. User builds need explicit `-fno-omit-frame-pointer`. Otherwise prefer DWARF or LBR when supported.
- `std::execution::par_unseq` / `unseq` require vectorization-safe bodies — no locks, no synchronizing calls. Memory allocation is explicitly permitted, and violations are undefined behavior, not compile errors. Details, standard references, and which standard libraries actually parallelize: `references/parallelism-and-contention.md`.
- `std::pmr::monotonic_buffer_resource` is **not thread-safe**. Use `synchronized_pool_resource` for multi-threaded callers.
- `std::hardware_destructive_interference_size` is not ABI-stable. GCC warns by default (`-Winterference-size`) when it is used in a header. Either hard-code 64 (or 128 for Apple Silicon / Intel adjacent-line prefetch) inside an internal-only TU, or guard with `#ifdef __cpp_lib_hardware_interference_size`.
- `kernel.perf_event_paranoid=2` (the upstream default) already allows per-process counting and user-space sampling of hardware events (`cycles:u`, `instructions:u`). Kernel profiling needs `<=1`; system-wide monitoring (`perf stat -a`, `perf top`, uncore events) needs `<=0` or root/`CAP_PERFMON`. Debian/Ubuntu kernels raise the default above `2` (3/4), which denies unprivileged perf entirely.
- Thermal throttling silently ruins benchmarks. Pin governor with `cpupower frequency-set -g performance` and watch `turbostat --interval 1` for `PkgWatt` / `Avg_MHz` excursions during runs.
- NUMA effects can dominate multisocket scaling. Inspect topology with `numactl --hardware` or `lstopo`.
- PMU counters are often unavailable in VMs and containers (`perf stat` shows `<not supported>`). Cachegrind/Callgrind are slow but useful when hardware counters are unavailable or noisy.
- More aggressive math flags (`-Ofast`, `-ffast-math`) can change numerical behavior. Treat them as semantics changes.
- Sanitizer-instrumented binaries are correctness tools, not performance baselines.

## Reference files

Load only the files relevant to the current bottleneck:

| File | Contents | Load when |
|---|---|---|
| `references/measurement-and-benchmarking.md` | Baseline design, benchmark hygiene, Google Benchmark, `perf stat`, TMA top-down, result comparison, pinning, NUMA, thermal throttling | Setting up measurements or interpreting counter data |
| `references/compiler-build-and-remarks.md` | CMake build modes, Clang/GCC optimization remarks, instrumented PGO, AutoFDO/CSSPGO, LTO/ThinLTO, BOLT, function multi-versioning | Tuning builds or diagnosing missed inlining/vectorization |
| `references/memory-layout-and-allocations.md` | Locality, `std::pmr`, false sharing, allocator alternatives (mimalloc/tcmalloc/jemalloc), flat hash maps, THP, `std::vector<bool>` trap | Backend Bound → Memory, allocation churn, or footprint work |
| `references/parallelism-and-contention.md` | OpenMP, oneTBB, `std::execution`, contention reduction, atomics cost, NUMA, race-checking | Poor scaling, contention, or parallelizing code |
| `references/cpp-language-patterns.md` | Source-level patterns: `noexcept` moves, RVO, `shared_ptr`/`std::function` cost, devirtualization, string/SSO, exceptions, stream I/O | Reviewing or writing hot-path C++ source |
| `references/tool-recipes.md` | Copy-paste workflows for `perf`, `perf c2c`, `perf mem`, FlameGraph, Valgrind tools, Heaptrack, hyperfine, bloaty, BOLT, `llvm-mca`, coz, non-Linux platforms | Running a specific tool |
| `references/review-checklist.md` | Static review rubric for code that cannot be run locally | Static performance review |

## Bundled scripts

Execute these with `bash` (do not inline their contents). They print usage on missing arguments and degrade gracefully when optional tools are absent.

| Script | What it does | Run when |
|---|---|---|
| `scripts/check-tools.sh` | Reports which profiling tools are installed plus `perf_event_paranoid`, governor, and CPU info | First, to see what the environment supports |
| `scripts/run-perf-stat.sh <binary> [args]` | Repeated `perf stat` counter summary (env: `PERF_REPEAT`, `PERF_EVENTS`, `CPUSET`, `NUMA_NODE`) | Counter-level triage and before/after comparisons |
| `scripts/run-perf-record.sh <binary> [args]` | `perf record` + optional FlameGraph SVG (env: `PERF_FREQ`, `PERF_CALLGRAPH`, `FLAMEGRAPH_DIR`, `CPUSET`, `NUMA_NODE`) | Locating CPU hotspots |
| `scripts/run-google-benchmark.sh <bench-binary>` | Runs a Google Benchmark binary with repetitions, warmup, and JSON output (env: `BENCH_REPS`, `BENCH_WARMUP`, `BENCH_FILTER`) | Microbenchmark runs you want to keep comparable |
| `scripts/collect-compiler-remarks.sh <clang\|gcc> <out-dir> -- <compile-cmd>` | Wraps one compile command and collects optimization remarks/records into `<out-dir>` | Diagnosing missed inlining/vectorization |
