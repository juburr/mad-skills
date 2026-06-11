#!/usr/bin/env bash
# Reports which C++ performance-analysis tools are installed and prints basic
# system/profiling configuration. Read-only diagnostics: safe to execute, makes
# no changes to the system.
set -euo pipefail

tools=(
  c++ clang++ g++ cmake ninja make
  taskset numactl numastat lstopo
  valgrind callgrind_annotate cg_annotate ms_print
  heaptrack llvm-mca llvm-profdata llvm-profgen llvm-bolt perf2bolt
  hyperfine bloaty coz pcm-memory
  cpupower turbostat
  python3
)

printf '%-24s %s\n' "TOOL" "STATUS"
printf '%-24s %s\n' "----" "------"

# perf needs a functional probe, not just `command -v`: on Debian/Ubuntu,
# /usr/bin/perf is a wrapper that fails when linux-tools for the running
# kernel is not installed.
if perf_version="$(perf --version 2>/dev/null)"; then
  printf '%-24s %s\n' "perf" "found: ${perf_version}"
else
  printf '%-24s %s\n' "perf" "missing or non-functional (install linux-tools matching: $(uname -r))"
fi

for tool in "${tools[@]}"; do
  if command -v "$tool" >/dev/null 2>&1; then
    printf '%-24s %s\n' "$tool" "found: $(command -v "$tool")"
  else
    printf '%-24s %s\n' "$tool" "missing"
  fi
done

# FlameGraph (https://github.com/brendangregg/FlameGraph) is a script
# collection, not a binary on PATH; locate it via FLAMEGRAPH_DIR if set.
if [[ -n "${FLAMEGRAPH_DIR:-}" ]]; then
  if [[ -x "${FLAMEGRAPH_DIR}/stackcollapse-perf.pl" && -x "${FLAMEGRAPH_DIR}/flamegraph.pl" ]]; then
    printf '%-24s %s\n' "FlameGraph" "found: ${FLAMEGRAPH_DIR}"
  else
    printf '%-24s %s\n' "FlameGraph" "FLAMEGRAPH_DIR set but stackcollapse-perf.pl/flamegraph.pl not executable there"
  fi
else
  printf '%-24s %s\n' "FlameGraph" "FLAMEGRAPH_DIR not set"
fi

echo
echo "System:"
uname -a || true

if command -v nproc >/dev/null 2>&1; then
  echo "Logical CPUs: $(nproc)"
fi

if command -v lscpu >/dev/null 2>&1; then
  echo "CPU model: $(lscpu | awk -F: '/Model name/ {gsub(/^[ \t]+/, "", $2); print $2; exit}')"
fi

if [[ -r /proc/sys/kernel/perf_event_paranoid ]]; then
  echo "perf_event_paranoid: $(cat /proc/sys/kernel/perf_event_paranoid)"
  echo "  (2 = per-process user-space profiling OK (upstream default); <=1 adds kernel profiling; <=0 adds system-wide monitoring; >2 (Debian/Ubuntu default) = unprivileged perf denied)"
fi
