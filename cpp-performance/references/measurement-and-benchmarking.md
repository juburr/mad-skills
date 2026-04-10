# Measurement and benchmarking

## What to measure

Pick the main metric before touching code:

- wall-clock latency (`p50`, `p95`, `p99`) for request/response paths
- throughput (ops/s, MB/s, req/s) for batch or server workloads
- CPU time for pure compute kernels
- peak RSS / resident memory
- allocations per operation
- scalability: speedup vs 1 thread, efficiency vs thread count

If the code is memory-sensitive, collect **runtime and memory** separately. A faster function that doubles RSS can still be a regression.

## Use the right benchmark level

### End-to-end benchmark
Best for:
- request handlers
- pipelines
- compilers, parsers, storage engines, services
- anything with user-visible latency or throughput

Prefer this first. It captures instruction mix, caches, allocator behavior, and synchronization more honestly than a tiny kernel benchmark.

### Subsystem benchmark
Best for:
- parsers
- codecs
- storage layers
- allocators
- schedulers
- queues

Useful when end-to-end runs are too slow or too noisy for iteration.

### Microbenchmark
Best for:
- small kernels
- alternative container or algorithm choices
- string parsing primitives
- hash/look-up kernels
- vectorized loops

Use this only when you can isolate the operation cleanly and keep setup cost out of the timing loop.

## Benchmark hygiene

- Use an optimized build with debug info.
- Keep inputs realistic: shape, size, skew, and thread count should resemble production or the target workload.
- Warm up caches/JIT-like one-time effects before trusting results.
- Repeat enough times to see variance.
- Pin cores when possible.
- On NUMA machines, keep CPU placement and memory placement stable.
- Record compiler, flags, CPU model, input description, and benchmark command.
- Compare like with like: identical outputs, identical correctness constraints.

Common failure modes:
- timing setup and teardown instead of the operation
- benchmark data that is too small and fits unnaturally in cache
- perfect branch predictability in synthetic loops
- hidden I/O or logging in the measured region
- comparing different semantics

## Google Benchmark defaults worth using

Google Benchmark supports repetitions, warmup, multithreaded runs, aggregated reporting, and JSON export.

Recommended starter flags:
```bash
./my_bench   --benchmark_repetitions=10   --benchmark_report_aggregates_only=true   --benchmark_min_warmup_time=0.2   --benchmark_out=benchmark.json   --benchmark_out_format=json
```

For code that runs with multiple threads:
- use `Threads(N)` or `ThreadRange(min, max)`
- prefer `UseRealTime()` when wall time is the metric
- use `MeasureProcessCPUTime()` when total CPU consumption matters

Example benchmark shape:
```cpp
static void BM_Parse(benchmark::State& state) {
  auto input = MakeRepresentativeInput(state.range(0));
  for (auto _ : state) {
    benchmark::DoNotOptimize(Parse(input));
  }
}
BENCHMARK(BM_Parse)
    ->Arg(1 << 10)
    ->Arg(1 << 20)
    ->Repetitions(10)
    ->ReportAggregatesOnly(true);
```

## `perf stat`: first pass for CPU-bound work

Use `perf stat` when you want a fast view of whether the program is limited by instructions, branches, or memory traffic.

Starter command:
```bash
taskset -c 2 perf stat -d -r 10 \
  -e cycles,instructions,branches,branch-misses,cache-references,cache-misses \
  -- ./build/bin/my_app --input corpus.txt
```

`-d` adds detailed cache events; it can be repeated up to three times for more depth. `-r 10` repeats the run and reports mean ± stddev (max 100).

What to look at:
- **time**: obvious first check
- **instructions**: did the change actually remove work?
- **IPC** (`instructions / cycles`): rough clue about pipeline efficiency
- **branch-miss rate**: often reveals unpredictable control flow
- **cache-miss rate**: often reveals locality problems or bandwidth pressure

Interpret cautiously:
- lower instructions with equal runtime can mean memory stalls got worse
- higher IPC alone does not prove the program is faster
- fewer cache misses may still lose if synchronization or algorithmic work increased

### Actionable events beyond the defaults

| Event | Why it matters |
|---|---|
| `LLC-loads`, `LLC-load-misses` | Last-level cache pressure; high miss rate suggests bandwidth or footprint problems |
| `dTLB-load-misses`, `iTLB-load-misses` | TLB pressure; mitigations include huge pages and reducing working-set fragmentation |
| `mem_load_retired.l3_miss` (Intel) | Precise sampling of L3 misses; pair with `perf record` for attribution |
| `cycle_activity.stalls_l3_miss` (Intel) | Time actually spent waiting on L3 misses |
| `uncore_imc_*/cas_count_read/`, `uncore_imc_*/cas_count_write/` | Memory controller traffic — proxy for DRAM bandwidth |
| `offcore_response.*` | Source of off-core requests; useful for NUMA traffic |

`pmu-tools` (andikleen/pmu-tools) ships `ocperf.py`, which lets you write symbolic event names like `mem_load_retired.l3_miss` instead of raw event codes.

## Top-Down Microarchitecture Analysis (TMA)

Before guessing whether a hot kernel is bound on the frontend, the backend, branch mispredictions, or just retiring well, ask the CPU. Modern Intel and AMD parts expose the Top-Down methodology directly through `perf`:

```bash
perf stat -M TopdownL1 -- ./build/bin/my_app --input corpus.txt
```

Level 1 splits cycles into four buckets:
- **Frontend Bound** — instruction supply problem (icache, decoder, BTB, branch resteers). Look at code layout, inlining, BOLT/PGO, branch density.
- **Bad Speculation** — branch mispredictions and machine clears. Look at unpredictable branches, atomic conflicts, self-modifying code.
- **Backend Bound — Memory** — pipeline stalled on loads/stores. Drop into the memory-layout reference.
- **Backend Bound — Core** — execution-port pressure or long-latency math. Usually wants vectorization, ILP, or algorithmic change.
- **Retiring** — pipeline is doing useful work. Algorithmic work is your remaining lever.

For more detail, use `-M TopdownL2` (or `--td-level=2`). Add `-I 1000` to see how the bucket mix shifts over a long-running workload. `andikleen/pmu-tools` provides `toplev.py`, which automates multi-level drilldown and per-function attribution.

TMA needs a recent CPU and may need elevated PMU access (`kernel.perf_event_paranoid=1` or lower).

## `hyperfine`: end-to-end CLI A/B

When the unit of work is a CLI invocation (compiler, parser, conversion tool, batch job), `hyperfine` is the lowest-friction way to compare two builds with statistically meaningful warmup and repetition:

```bash
hyperfine --warmup 3 --runs 20 \
  './build-before/bin/my_app --input corpus.txt' \
  './build-after/bin/my_app --input corpus.txt'
```

Outputs mean, stddev, min, max, and a relative speedup ratio. Supports `--export-markdown`, `--export-json`, and `--export-csv`. Reach for it when Google Benchmark is overkill but `time` is too noisy.

## Core pinning and NUMA

Use `taskset` to keep runs on a stable CPU set when you need repeatability:
```bash
taskset -c 2 ./build/bin/my_app
```

On NUMA hardware, place both CPU execution and memory on the same node for a cleaner baseline:
```bash
numactl --cpunodebind=0 --membind=0 -- ./build/bin/my_app
numactl --hardware                       # inspect node topology and free memory
numastat -p $(pidof my_app)              # per-node memory residency for a live process
lstopo                                   # full hardware topology (hwloc) — caches, NUMA, cores
```

If scaling regresses sharply across sockets, suspect remote memory access, false sharing, or memory bandwidth pressure.

## Thermal throttling and frequency scaling

Frequency scaling and thermal throttling silently distort benchmarks, especially on laptops and dense servers. Before trusting numbers:

```bash
sudo cpupower frequency-set -g performance      # pin governor
turbostat --interval 1 -- ./build/bin/my_app    # watch Avg_MHz, Bzy_MHz, PkgWatt for excursions
```

On long runs, monitor `/sys/class/thermal/thermal_zone*/temp` or `sensors` to confirm the package isn't throttling.

## Short inner loops

For tiny kernels, once a real profiler already identified the hot loop, `llvm-mca` can help reason about instruction throughput and backend resource pressure from generated assembly.

Use it as a microscope, not as a substitute for end-to-end measurement.

## Record results in a reviewable way

Prefer a compact table like this:

| Metric | Before | After | Delta | Notes |
|---|---:|---:|---:|---|
| wall time |  |  |  | |
| instructions |  |  |  | |
| branch-miss % |  |  |  | |
| cache-miss % |  |  |  | |
| peak RSS |  |  |  | |
| allocations/op |  |  |  | |

The important property is **repeatability**, not decorative formatting.
