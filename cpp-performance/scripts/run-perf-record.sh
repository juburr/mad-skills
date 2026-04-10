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
data_file="$out_dir/${name}__${timestamp}.data"
script_file="$out_dir/${name}__${timestamp}.script.txt"
folded_file="$out_dir/${name}__${timestamp}.folded"
svg_file="$out_dir/${name}__${timestamp}.svg"

freq="${PERF_FREQ:-999}"
callgraph="${PERF_CALLGRAPH:-dwarf,16384}"

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

record_cmd=(perf record -F "${freq}" -g --call-graph "${callgraph}" -o "${data_file}" -- "${runner[@]}" "${program[@]}")

echo "Running perf record:" >&2
printf '  %q' "${record_cmd[@]}" >&2
echo >&2

"${record_cmd[@]}"

echo "perf data: $data_file" >&2
echo "To inspect interactively: perf report -i $data_file" >&2

perf script -i "${data_file}" > "${script_file}"
echo "perf script output: $script_file" >&2

if [[ -n "${FLAMEGRAPH_DIR:-}" ]] && [[ -x "${FLAMEGRAPH_DIR}/stackcollapse-perf.pl" ]] && [[ -x "${FLAMEGRAPH_DIR}/flamegraph.pl" ]]; then
  "${FLAMEGRAPH_DIR}/stackcollapse-perf.pl" "${script_file}" > "${folded_file}"
  "${FLAMEGRAPH_DIR}/flamegraph.pl" "${folded_file}" > "${svg_file}"
  echo "Folded stacks: $folded_file" >&2
  echo "Flame graph:   $svg_file" >&2
else
  echo "FLAMEGRAPH_DIR not set (or scripts not executable); skipping flame graph generation." >&2
fi
