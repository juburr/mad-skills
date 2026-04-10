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

cmd=(perf stat -d -r "${repeat}" -e "${events}" -o "${out_file}" -- "${runner[@]}" "${program[@]}")

echo "Running perf stat:" >&2
printf '  %q' "${cmd[@]}" >&2
echo >&2

"${cmd[@]}"

echo "perf stat output: $out_file" >&2
cat "$out_file"
