# Compiler, build, and optimization remarks

## Build mode

For profiling and most optimization work, prefer:

- **CMake**: `RelWithDebInfo`
- or `Release` with debug info enabled

Typical CMake build setup:
```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
cmake --build build -j
```

`RelWithDebInfo` defaults to `-O2 -g -DNDEBUG` for GCC/Clang (not `-O3`). It keeps optimization enabled while preserving symbols for profilers and debuggers. If you need `-O3`, override `CMAKE_CXX_FLAGS_RELWITHDEBINFO` or use a custom build type.

## CMake patterns

### Per-target compile flags
```cmake
target_compile_options(my_target PRIVATE
  $<$<CXX_COMPILER_ID:Clang,GNU>:-O3 -g>
  $<$<CXX_COMPILER_ID:MSVC>:/O2 /Zi>
)
```

### Per-target link flags
```cmake
target_link_options(my_target PRIVATE
  $<$<CXX_COMPILER_ID:Clang,GNU>:-g>
  $<$<CXX_COMPILER_ID:MSVC>:/DEBUG>
)
```

### Enable IPO/LTO when supported
```cmake
include(CheckIPOSupported)
check_ipo_supported(RESULT ipo_supported OUTPUT ipo_error)
if(ipo_supported)
  set_property(TARGET my_target PROPERTY INTERPROCEDURAL_OPTIMIZATION TRUE)
endif()
```

Use this for release-style builds when whole-program optimization is worth the extra build cost.

## Frame pointers and call graphs

If Linux `perf` call stacks matter, consider:
```cmake
target_compile_options(my_target PRIVATE
  $<$<CXX_COMPILER_ID:Clang,GNU>:-fno-omit-frame-pointer>
)
```

This is especially useful if you want `perf record --call-graph fp`. If you cannot or do not want to keep frame pointers, prefer DWARF unwinding in `perf`.

## Clang optimization remarks

Clang can emit optimization remarks when the compiler:
- applied a transformation
- missed a transformation
- analyzed whether a transformation was possible

Useful starter flags:
```bash
clang++ -O3 -g   -Rpass=.*   -Rpass-missed=.*   -Rpass-analysis=.*   -fsave-optimization-record   -c foo.cpp -o foo.o
```

Practical uses:
- confirm whether a loop vectorized
- learn why vectorization failed
- see inlining decisions
- inspect unrolling or missed unrolling
- focus on remarks in hot code first

If the remark volume is too high, narrow the regex to specific passes such as `inline` or `loop-vectorize`.

## GCC optimization remarks

GCC provides text optimization reports and pass dumps.

Starter flags:
```bash
g++ -O3 -g \
  -fopt-info \
  -fopt-info-vec-missed \
  -fsave-optimization-record \
  -c foo.cpp -o foo.o
```

`-fsave-optimization-record` (GCC 9+) writes a gzipped JSON file at `<source>.opt-record.json.gz` — note that GCC emits **JSON**, while Clang emits **YAML** at `<input>.opt.yaml`. Tooling that consumes one rarely consumes the other.

When you need deeper compiler internals:
```bash
g++ -O3 -g -fdump-passes -c foo.cpp -o foo.o
```

Use these reports to answer questions like:
- was the loop vectorized?
- why was vectorization missed?
- which inlining opportunities were accepted or rejected?
- which GCC pass is relevant to the issue?

## Avoid the lazy `-Ofast` reflex

Do not use `-Ofast` as an unexamined default. It changes semantics. If relaxed floating-point behavior is actually acceptable, document that decision and validate numerics. Otherwise, stay with conforming optimization flags.

## PGO

Profile-guided optimization is worth trying when:
- the code path is stable and heavily used
- representative workloads exist
- you already removed obvious algorithmic and locality bottlenecks
- whole-program optimization plausibly matters

### Clang instrumentation PGO
```bash
# 1) build instrumented
clang++ -O3 -fprofile-generate -g code.cc -o code

# 2) run representative workloads
LLVM_PROFILE_FILE="code-%p.profraw" ./code --realistic-input

# 3) merge profiles
llvm-profdata merge -output=code.profdata code-*.profraw

# 4) rebuild using the profile
clang++ -O3 -fprofile-use=code.profdata -g code.cc -o code
```

### GCC instrumentation PGO
```bash
# 1) build instrumented
g++ -O3 -fprofile-generate -g code.cc -o code

# 2) run representative workloads
./code --realistic-input

# 3) rebuild using the generated profile
g++ -O3 -fprofile-use -g code.cc -o code
```

Notes:
- instrumented binaries must run on representative inputs
- stale or mismatched profiles can mislead the compiler
- PGO is most useful when branch probabilities, inlining, and code layout matter

### Sample-based PGO (AutoFDO / CSSPGO)

If you already have production `perf` profiles, you can skip the instrumented-build step and use sample-based PGO. There is no instrumented binary to deploy, and the same profile can drive multiple rebuilds.

```bash
# 1) build with debug info
clang++ -O2 -g -fdebug-info-for-profiling -o code code.cc

# 2) collect samples in production (LBR strongly recommended on Intel)
perf record -b -o perf.data -- ./code --realistic-input

# 3) convert perf.data to LLVM sample profile
#    create_llvm_prof from github.com/google/autofdo, OR llvm-profgen shipped with LLVM
llvm-profgen --binary=code --output=code.prof --perfdata=perf.data

# 4) rebuild using the sample profile
clang++ -O2 -fprofile-sample-use=code.prof -o code code.cc
```

CSSPGO (Context-Sensitive Sampling PGO, LLVM 14+) extends AutoFDO with caller-context awareness via pseudo-probes (`-fpseudo-probe-for-profiling`) and typically recovers most of the gap to instrumented PGO.

GCC's equivalent uses `-fauto-profile=<gcov-file>`, with the profile produced by AutoFDO's `create_gcov` tool.

## LTO and ThinLTO

Use LTO/ThinLTO after hotspot-level fixes or as a release-build optimization pass.

Typical CMake route:
- enable IPO with `INTERPROCEDURAL_OPTIMIZATION`
- verify support with `CheckIPOSupported`

ThinLTO is usually the easier whole-program option when link-time scalability matters because the optimization backends can run in parallel.

## BOLT (post-link layout optimization)

BOLT (`llvm-bolt`, upstreamed to LLVM in version 14) is a post-link binary rewriter that optimizes code layout and basic-block ordering using a `perf` profile. It runs *after* the linker, on top of an already-optimized PGO+LTO binary.

```bash
# 1) build with relocations preserved (required by BOLT)
clang++ -O3 -flto -Wl,-q -o code code.cc

# 2) collect a representative profile (LBR strongly preferred on Intel)
perf record -e cycles:u -j any,u -o perf.data -- ./code --realistic-input

# 3) convert and apply
perf2bolt -p perf.data -o code.fdata code
llvm-bolt code -o code.bolt -data=code.fdata \
  -reorder-blocks=ext-tsp -reorder-functions=cdsort -split-functions \
  -split-all-cold -split-eh -dyno-stats
```

When to reach for BOLT:
- the binary is large and frontend-bound (icache, iTLB, branch resteers)
- PGO+LTO are already in place and you need a few more percent
- you can collect a representative production profile

Reported gains on large binaries (Clang, GCC, server workloads at Meta) range from 5–15% on top of PGO+LTO. Small CPU-bound microbenchmarks rarely benefit.

## Runtime CPU dispatch (function multi-versioning)

When portability matters but you also want AVX2/AVX-512 on CPUs that support them, GCC and Clang provide function multi-versioning instead of building per-CPU binaries:

```cpp
__attribute__((target_clones("default,avx2,avx512f")))
void hot_kernel(float* out, const float* a, const float* b, size_t n) {
  for (size_t i = 0; i < n; ++i) out[i] = a[i] + b[i];
}
```

The compiler emits multiple versions and an IFUNC resolver picks the best at load time. Cleaner than `#ifdef` ladders or runtime feature checks for hand-written intrinsics.

## `-march=native` and `-march=x86-64-v3`

`-march=native` is useful for local experiments on a known machine. Do not silently bake it into portable release builds unless the deployment target is fixed and documented.

For portable deployment to a known fleet baseline, target a microarchitecture level instead: `-march=x86-64-v2` (SSE4.2), `-march=x86-64-v3` (AVX2 + BMI2), or `-march=x86-64-v4` (AVX-512). Binaries built for a level still crash with SIGILL on older hardware, so verify the floor.

## What compiler remarks are good for

Compiler remarks are not the benchmark. They are evidence about **why codegen did or did not happen**.

Use them to:
- confirm a hypothesis from the profiler
- decide whether code shape is blocking vectorization or inlining
- avoid blind source rewrites
- explain performance changes in code review
