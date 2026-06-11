#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <program> [args...]" >&2
  exit 1
fi

if ! command -v perf >/dev/null 2>&1; then
  echo "perf is not installed." >&2
  exit 1
fi

program=("$@")
timestamp="$(date +%Y%m%d-%H%M%S)"
out_dir="${PERF_OUT_DIR:-perf-results}"
mkdir -p "$out_dir"

name="$(basename "$1")"
out_file="$out_dir/${name}__${timestamp}.stat.txt"

events="${PERF_EVENTS:-cycles,instructions,branches,branch-misses,cache-references,cache-misses}"
# Median of 5 runs balances runtime vs noise.
repeat="${PERF_REPEAT:-5}"

runner=()
if [[ -n "${NUMA_NODE:-}" ]]; then
  if command -v numactl >/dev/null 2>&1; then
    runner+=(numactl --cpunodebind="${NUMA_NODE}" --membind="${NUMA_NODE}" --)
  else
    echo "NUMA_NODE was provided but numactl is not installed; ignoring NUMA pinning." >&2
  fi
fi

if [[ -n "${CPUSET:-}" ]]; then
  if command -v taskset >/dev/null 2>&1; then
    runner+=(taskset -c "${CPUSET}")
  else
    echo "CPUSET was provided but taskset is not installed; ignoring CPU pinning." >&2
  fi
fi

# -d adds a standard detailed event set that overlaps the explicit -e list;
# both are counted and multiplexing pressure rises. The overlap is accepted
# for convenience.
cmd=(perf stat -d -r "${repeat}" -e "${events}" -o "${out_file}" -- "${runner[@]}" "${program[@]}")

echo "Running perf stat:" >&2
printf '  %q' "${cmd[@]}" >&2
echo >&2

# Capture the measured program's exit status without letting set -e abort us:
# perf stat may still have written useful counter output.
status=0
"${cmd[@]}" || status=$?

if [[ "$status" -ne 0 ]]; then
  echo "Warning: measured program exited non-zero (status: $status)." >&2
fi

echo "perf stat output: $out_file" >&2
if [[ -e "$out_file" ]]; then
  cat "$out_file"
fi

exit "$status"
