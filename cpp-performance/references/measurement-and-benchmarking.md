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
./my_bench \
  --benchmark_repetitions=10 \
  --benchmark_display_aggregates_only=true \
  --benchmark_min_warmup_time=0.2 \
  --benchmark_out=benchmark.json \
  --benchmark_out_format=json
```

`--benchmark_min_warmup_time` requires Google Benchmark >= 1.7; older binaries abort on unknown `--benchmark_` flags. Use `display_aggregates_only` (not `report_aggregates_only`): it declutters the console but keeps per-repetition samples in the JSON, which `tools/compare.py` below needs; `report_aggregates_only` strips them from the file output too.

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

### Comparing results

- Compare old-vs-new JSON with Google Benchmark's `tools/compare.py`, which runs a Mann-Whitney U test (needs `scipy`; use >= 9 repetitions for the test to be meaningful):
  ```bash
  tools/compare.py benchmarks before.json after.json
  ```
- Prefer medians and distributions over single means; a mean hides bimodal noise.
- Discard first-run cold-start outliers before comparing.
- In noisy environments, `--benchmark_enable_random_interleaving` interleaves repetitions across benchmarks, reducing drift bias.

## `perf stat`: first pass for CPU-bound work

Use `perf stat` when you want a fast view of whether the program is limited by instructions, branches, or memory traffic.

Starter command:
```bash
taskset -c 2 perf stat -d -r 10 \
  -e cycles,instructions,branches,branch-misses,cache-references,cache-misses \
  -- ./build/bin/my_app --input corpus.txt
```

`-d` adds detailed cache events; it can be repeated up to three times for more depth. Several `-d` events (e.g. `LLC-loads`) report `<not supported>` on AMD and virtualized hosts. `-r 10` repeats the run and reports mean ± stddev (max 100).

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
| `uncore_imc_*/cas_count_read/`, `uncore_imc_*/cas_count_write/` | Memory controller traffic — proxy for DRAM bandwidth. Counts system-wide only (`-a` required); Intel server parts — client parts expose `uncore_imc/data_reads/` etc. |
| `offcore_response.*` | Source of off-core requests; useful for NUMA traffic |

Modern `perf` resolves symbolic event names like `mem_load_retired.l3_miss` natively from built-in JSON event tables; `ocperf.py` from `pmu-tools` (andikleen/pmu-tools) is only needed for events missing from the installed perf's tables.

## Top-Down Microarchitecture Analysis (TMA)

Before guessing whether a hot kernel is bound on the frontend, the backend, branch mispredictions, or just retiring well, ask the CPU. Modern Intel and AMD parts expose the Top-Down methodology directly through `perf`:

```bash
perf stat -M TopdownL1 -- ./build/bin/my_app --input corpus.txt    # Intel
perf stat -M PipelineL1 -- ./build/bin/my_app --input corpus.txt   # AMD Zen 4+ (no TopdownL1 group on AMD)
```

Level 1 apportions pipeline slots (not cycles) into four buckets:
- **Frontend Bound** — instruction supply problem (icache, decoder, BTB, branch resteers). Look at code layout, inlining, BOLT/PGO, branch density.
- **Bad Speculation** — branch mispredictions and machine clears. Look at unpredictable branches, atomic conflicts, self-modifying code.
- **Backend Bound** — pipeline stalled on execution resources. Level 2 splits this into **Memory** (stalled on loads/stores — drop into the memory-layout reference) vs **Core** (execution-port pressure or long-latency math — usually wants vectorization, ILP, or algorithmic change).
- **Retiring** — pipeline is doing useful work. Algorithmic work is your remaining lever.

For Level 2, use `-M TopdownL2` (Intel) or `-M PipelineL2` (AMD, which splits backend_bound_memory vs backend_bound_cpu). On Icelake and newer Intel, `perf stat --topdown --td-level=2` also works; `--td-level` is only valid with `--topdown`, not as a standalone alternative to `-M TopdownL2`. Add `-I 1000` to see how the bucket mix shifts over a long-running workload. `andikleen/pmu-tools` provides `toplev.py`, which automates multi-level drilldown and per-function attribution.

TMA needs a recent CPU. Per-process `-M TopdownL1` works even at `kernel.perf_event_paranoid=2`; system-wide collection — `--topdown` on pre-Icelake Intel and uncore-based metrics — needs `perf_event_paranoid<=0`, root, or `CAP_PERFMON`.

## `hyperfine`: end-to-end CLI A/B

When the unit of work is a CLI invocation (compiler, parser, conversion tool, batch job), `hyperfine` is the lowest-friction way to compare two builds with statistically meaningful warmup and repetition. Reach for it when Google Benchmark is overkill but `time` is too noisy. Commands in `tool-recipes.md`.

## Core pinning and NUMA

Use `taskset` to keep runs on a stable CPU set when you need repeatability:
```bash
taskset -c 2 ./build/bin/my_app
```

ASLR adds run-to-run code/data layout variance; `setarch -R -- ./bench` disables it for diagnosis (don't report production numbers that way).

On NUMA hardware, place both CPU execution and memory on the same node for a cleaner baseline (`numactl`, `numastat`, `lstopo` — commands in `tool-recipes.md`).

If scaling regresses sharply across sockets, suspect remote memory access, false sharing, or memory bandwidth pressure.

## Thermal throttling and frequency scaling

Frequency scaling and thermal throttling silently distort benchmarks, especially on laptops and dense servers. Before trusting numbers:

```bash
sudo cpupower frequency-set -g performance      # pin governor
sudo turbostat --interval 1                     # second terminal: watch Avg_MHz, Bzy_MHz, PkgWatt while the benchmark runs
```

Run `turbostat` in a second terminal: with a trailing command it prints one summary at completion (`--interval` is ignored), so it cannot show excursions during the run. x86-only; needs root/MSR access.

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
