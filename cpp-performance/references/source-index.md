# Source index

This skill was built from current open documentation and primary sources, with an emphasis on portable agent-skill structure and modern C++ performance tooling.

## Skill format and compatibility

- OpenAI Codex skills documentation
- Anthropic Claude Code skills documentation
- Agent Skills open-standard ecosystem references
- GitHub Copilot / Agent Skills guidance (useful because it also targets the same open `SKILL.md` pattern)

## C++ performance and tooling

### Benchmarking and profiling
- Google Benchmark user guide
- Linux `perf` manual pages (`perf-stat`, `perf-record`, `perf-c2c`, `perf-mem`)
- Linux kernel perf Top-Down documentation (`tools/perf/Documentation/topdown.txt`)
- Brendan Gregg FlameGraph tools and "The Return of the Frame Pointers"
- Brendan Gregg "Linux perf Examples"
- Easyperf top-down methodology articles
- `taskset`, `numactl`, `numastat`, `lstopo` (hwloc), and `numa(7)` man pages
- `llvm-mca` command guide
- `hyperfine` (sharkdp/hyperfine)
- `bloaty` (google/bloaty)
- Intel PCM (`pcm-memory.x`), Intel TopDown methodology
- `pmu-tools` / `toplev.py` / `ocperf.py` (andikleen/pmu-tools)
- coz causal profiler

### Compiler and build optimization
- Clang Users Manual and diagnostics reference (Remarks, `-Rpass*`)
- GCC developer, instrumentation, and optimization docs (`-fopt-info`, `-fsave-optimization-record`, `-fauto-profile`)
- LLVM Remarks documentation
- AutoFDO (google/autofdo) and LLVM `llvm-profgen` / CSSPGO
- LLVM BOLT documentation (`llvm/llvm-project/bolt`)
- CMake docs for `CMAKE_BUILD_TYPE`, `target_compile_options`, `target_link_options`, `CheckIPOSupported`, and IPO/LTO support
- Fedora/Ubuntu frame-pointer policy announcements

### Memory and layout
- cppreference pages for `std::pmr::monotonic_buffer_resource` (and the `synchronized_pool_resource` thread-safety contract)
- cppreference pages for `std::hardware_destructive_interference_size` and the GCC `-Winterference-size` discussion
- cppreference pages for `std::span`, `std::string_view`, `std::execution`
- Abseil `flat_hash_map` / SwissTable design notes
- Boost.Unordered `unordered_flat_map` documentation
- jemalloc, tcmalloc (gperftools and google/tcmalloc), and Microsoft mimalloc documentation
- oneTBB memory allocation docs
- Linux Transparent Huge Pages and `madvise(2)` documentation

### Parallelism and correctness
- oneTBB docs
- OpenMP docs
- Clang Thread Safety Analysis
- AddressSanitizer, LeakSanitizer, and ThreadSanitizer docs
- Valgrind docs for Callgrind, Cachegrind, Massif, and DHAT
- Heaptrack docs

## Notes

The main `SKILL.md` intentionally stays concise and pushes detail into the `references/` folder so that tools following the open agent-skills pattern can load extra material only when needed.
