#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <benchmark-binary> [benchmark-args...]" >&2
  exit 1
fi

bin="$1"
shift || true

if [[ ! -x "$bin" ]]; then
  echo "Benchmark binary not executable: $bin" >&2
  exit 1
fi

timestamp="$(date +%Y%m%d-%H%M%S)"
out_dir="${BENCH_OUT_DIR:-benchmark-results}"
mkdir -p "$out_dir"

name="$(basename "$bin")"
json_out="$out_dir/${name}__${timestamp}.json"
txt_out="$out_dir/${name}__${timestamp}.txt"

reps="${BENCH_REPS:-10}"
warmup="${BENCH_WARMUP:-0.2}"

runner=()
if [[ -n "${CPUSET:-}" ]]; then
  if command -v taskset >/dev/null 2>&1; then
    runner=(taskset -c "$CPUSET")
  else
    echo "CPUSET was provided but taskset is not installed; ignoring CPU pinning." >&2
  fi
fi

cmd=(
  "${runner[@]}"
  "$bin"
  "--benchmark_repetitions=${reps}"
  "--benchmark_report_aggregates_only=true"
  "--benchmark_min_warmup_time=${warmup}"
  "--benchmark_out=${json_out}"
  "--benchmark_out_format=json"
)

if [[ -n "${BENCH_FILTER:-}" ]]; then
  cmd+=("--benchmark_filter=${BENCH_FILTER}")
fi

cmd+=("$@")

echo "Running benchmark:" >&2
printf '  %q' "${cmd[@]}" >&2
echo >&2

"${cmd[@]}" | tee "$txt_out"

echo "Text output: $txt_out" >&2
echo "JSON output: $json_out" >&2
