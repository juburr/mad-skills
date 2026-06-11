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

# 999 Hz: off-by-one from 1000 Hz to avoid lockstep sampling with kernel timers.
freq="${PERF_FREQ:-999}"
# dwarf,16384: user-stack bytes dumped per sample for DWARF unwinding; larger
# captures deeper stacks but inflates perf.data (max 65528).
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

# --call-graph implies -g, so -g is not passed separately.
record_cmd=(perf record -F "${freq}" --call-graph "${callgraph}" -o "${data_file}" -- "${runner[@]}" "${program[@]}")

echo "Running perf record:" >&2
printf '  %q' "${record_cmd[@]}" >&2
echo >&2

# Capture the profiled program's exit status without letting set -e abort us:
# a failing program may still have produced useful profile data.
status=0
"${record_cmd[@]}" || status=$?

if [[ ! -e "$data_file" ]]; then
  echo "perf record produced no data file (exit status: $status)." >&2
  # Never exit 0 from this branch even if perf itself reported success.
  exit "$(( status == 0 ? 1 : status ))"
fi

if [[ "$status" -ne 0 ]]; then
  echo "Warning: profiled program exited non-zero (status: $status); continuing with post-processing." >&2
fi

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

exit "$status"
