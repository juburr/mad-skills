#!/usr/bin/env bash
set -euo pipefail

tools=(
  c++ clang++ g++ cmake ninja make
  perf taskset numactl numastat lstopo
  valgrind callgrind_annotate cg_annotate ms_print
  heaptrack llvm-mca llvm-profdata llvm-profgen llvm-bolt perf2bolt
  hyperfine bloaty
  cpupower turbostat
  python3
)

printf '%-24s %s\n' "TOOL" "STATUS"
printf '%-24s %s\n' "----" "------"
for tool in "${tools[@]}"; do
  if command -v "$tool" >/dev/null 2>&1; then
    printf '%-24s %s\n' "$tool" "found: $(command -v "$tool")"
  else
    printf '%-24s %s\n' "$tool" "missing"
  fi
done

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
fi
