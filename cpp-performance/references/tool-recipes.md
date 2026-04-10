# Tool recipes

These are copy-paste starting points. Adjust paths, inputs, and thread counts for the repository in front of you.

## Setup: point `$SKILL_DIR` at this skill

All `scripts/...` paths below are relative to the `cpp-performance` skill directory, **not** the target project. Before running any recipe below, export `SKILL_DIR` once per shell, pointing at wherever this skill is installed:

```bash
# Pick the path that matches your install:
export SKILL_DIR="$HOME/.claude/skills/cpp-performance"           # Claude Code
# export SKILL_DIR="$HOME/.codex/skills/cpp-performance"          # Codex
# export SKILL_DIR="$HOME/go/src/github.com/juburr/mad-skills/cpp-performance"  # repo checkout
```

If you'd rather not set a variable, `cd "$SKILL_DIR"` once and drop the `"$SKILL_DIR"/` prefix in the commands. Every command below fails with `No such file or directory` if `$SKILL_DIR` is unset.

## Check available tools

```bash
bash "$SKILL_DIR"/scripts/check-tools.sh
```

## Google Benchmark run

```bash
bash "$SKILL_DIR"/scripts/run-google-benchmark.sh ./build/benchmarks/my_bench
```

Optional environment variables:
- `BENCH_FILTER`
- `BENCH_REPS`
- `BENCH_WARMUP`
- `BENCH_OUT_DIR`
- `CPUSET`

## `perf stat`

```bash
bash "$SKILL_DIR"/scripts/run-perf-stat.sh ./build/bin/my_app --input corpus.txt
```

Optional environment variables:
- `CPUSET` — for `taskset -c`
- `NUMA_NODE` — for `numactl --cpunodebind/--membind`
- `PERF_EVENTS`
- `PERF_REPEAT`
- `PERF_OUT_DIR`

## `perf record`

```bash
bash "$SKILL_DIR"/scripts/run-perf-record.sh ./build/bin/my_app --input corpus.txt
```

Optional environment variables:
- `CPUSET`
- `NUMA_NODE`
- `PERF_FREQ`
- `PERF_CALLGRAPH`
- `PERF_OUT_DIR`
- `FLAMEGRAPH_DIR` — path to Brendan Gregg's FlameGraph repo if you want an SVG generated automatically

Starter choices:
- `PERF_CALLGRAPH=fp` when the binary has frame pointers
- `PERF_CALLGRAPH=dwarf,16384` when frame pointers are unavailable
- `PERF_CALLGRAPH=lbr` on supported Intel systems when you want very low overhead

After recording:
```bash
perf report -i perf-results/<file>.data
```

## FlameGraph from existing `perf.data`

```bash
perf script -i perf.data \
  | /path/to/FlameGraph/stackcollapse-perf.pl \
  | /path/to/FlameGraph/flamegraph.pl > flamegraph.svg
```

Recent `perf` (6.x) also ships a built-in shortcut: `perf script report flamegraph` produces an HTML flame graph without external scripts.

## `perf c2c`: false sharing and cache-line contention

```bash
perf c2c record -- ./build/bin/my_app --input corpus.txt
perf c2c report -NN -g --call-graph=dwarf
```

Look at the **Shared Data Cache Line Table** for lines with the highest HITM (load that hit a modified line in another core's cache). The **Shared Cache Line Distribution Pareto** shows the offsets within each contended line, which usually points straight at the offending struct fields.

`perf c2c` works on Intel (load-latency / precise-store), recent AMD (IBS, except Zen 3 — unsupported), PowerPC (random instruction sampling), and Arm64 (SPE).

## `perf mem`: memory access sampling

```bash
perf mem record -- ./build/bin/my_app
perf mem report --sort=mem,sym,dso
```

Reports the source location of loads/stores along with the cache level that satisfied each access. Useful when `perf c2c` is overkill but cache-miss attribution still matters.

## Memory bandwidth measurement

For DRAM bandwidth, use Intel PCM (`pcm-memory.x`, Apache-licensed) or `perf` uncore counters:

```bash
sudo pcm-memory.x 1                                          # interval seconds
sudo perf stat -e 'uncore_imc_*/cas_count_read/,uncore_imc_*/cas_count_write/' \
  -- ./build/bin/my_app
```

A STREAM benchmark (`stream_c.exe`) gives a portable upper bound for the machine's sustainable bandwidth — compare your workload's measured rate to that ceiling. If you're within ~70%, more compute parallelism cannot help.

## `hyperfine`: end-to-end CLI A/B

```bash
hyperfine --warmup 3 --runs 20 \
  --export-markdown bench.md \
  './build-before/bin/my_app --input corpus.txt' \
  './build-after/bin/my_app --input corpus.txt'
```

## `bloaty`: binary size and section breakdown

```bash
bloaty --csv -d compileunits,symbols ./build/bin/my_app | head -50
bloaty -d sections ./build/bin/my_app
bloaty ./build-after/bin/my_app -- ./build-before/bin/my_app   # diff two builds
```

Use when chasing icache pressure, template bloat, LTO size regressions, or unexpectedly large debug sections.

## Clang optimization remarks

```bash
clang++ -O3 -g   -Rpass=.* -Rpass-missed=.* -Rpass-analysis=.*   -fsave-optimization-record   -c foo.cpp -o foo.o
```

## GCC optimization remarks

```bash
g++ -O3 -g   -fopt-info   -fopt-info-vec-missed   -fsave-optimization-record   -c foo.cpp -o foo.o
```

## Bundled helper to collect remarks for a one-off compile command

```bash
bash "$SKILL_DIR"/scripts/collect-compiler-remarks.sh clang out -- \
  clang++ -O3 -c foo.cpp -o foo.o

bash "$SKILL_DIR"/scripts/collect-compiler-remarks.sh gcc out -- \
  g++ -O3 -c foo.cpp -o foo.o
```

## Sanitizers

### AddressSanitizer
```bash
clang++ -O1 -g -fno-omit-frame-pointer -fsanitize=address ...
```

### ThreadSanitizer
```bash
clang++ -O1 -g -fsanitize=thread ...
```

### Leak detection
```bash
clang++ -O1 -g -fsanitize=address ...
ASAN_OPTIONS=detect_leaks=1 ./your_binary
```

Treat these as correctness tools, not timing tools.

## Thread-safety analysis

```bash
clang++ -c -Wthread-safety example.cpp
```

Requires lock annotations to be useful.

## Valgrind family

### Callgrind
Use for instruction-level call graph analysis when hardware counters or `perf` are not available:
```bash
valgrind --tool=callgrind ./build/bin/my_app
callgrind_annotate callgrind.out.*
```

### Cachegrind
Use for comparative cache-oriented runs:
```bash
valgrind --tool=cachegrind ./build/bin/my_app
```

### Massif
Use for peak heap analysis:
```bash
valgrind --tool=massif ./build/bin/my_app
ms_print massif.out.*
```

### DHAT
Use for heap lifetime and churn analysis:
```bash
valgrind --tool=dhat ./build/bin/my_app
```

## Heaptrack

```bash
heaptrack ./build/bin/my_app
heaptrack_gui heaptrack.*.gz
```

If the GUI is unavailable, keep the capture and analyze it later on a workstation with the GUI installed.

## `llvm-mca`

Use only after the profiler points at a tiny hot kernel and you have its assembly:

```bash
clang++ -O3 -S -masm=intel foo.cpp -o foo.s
llvm-mca -mcpu=native foo.s
```

To analyze a specific region rather than the whole file, mark it in the assembly with `# LLVM-MCA-BEGIN <name>` / `# LLVM-MCA-END`. You can emit those from C++ with `__asm__ volatile("# LLVM-MCA-BEGIN region":::"memory")`, but the inline asm acts as an optimization barrier and can prevent vectorization or instruction scheduling — always diff the marker-bearing assembly against the marker-free build before trusting results.

llvm-mca is a static throughput/port-pressure estimator. It does not model branch mispredictions, cache misses, or memory subsystem effects. It is not a replacement for workload-level benchmarking.

## NUMA topology and placement

```bash
numactl --hardware                           # nodes, free memory, distances
lstopo                                       # full hwloc topology (caches, cores, NUMA)
numastat -p $(pidof my_app)                  # per-node memory residency for a running process
numactl --cpunodebind=0 --membind=0 -- ./build/bin/my_app
```

## BOLT (post-link optimization)

```bash
clang++ -O3 -flto -Wl,-q -o code code.cc
perf record -e cycles:u -j any,u -o perf.data -- ./code --realistic-input
perf2bolt -p perf.data -o code.fdata code
llvm-bolt code -o code.bolt -data=code.fdata \
  -reorder-blocks=ext-tsp -reorder-functions=cdsort \
  -split-functions -split-all-cold -split-eh -dyno-stats
```

Use after PGO+LTO on large, frontend-bound binaries. See `compiler-build-and-remarks.md` for context.

## Causal profiling: `coz`

```bash
clang++ -O2 -g -ldl -lcoz code.cc -o code
coz run --- ./code --realistic-input
```

`coz` answers "which function's speedup would actually shorten end-to-end latency?" by running virtual-speedup experiments on selected lines/functions. Especially useful when traditional CPU profiles point at code that is actually waiting on something else.
