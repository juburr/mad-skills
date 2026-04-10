#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  collect-compiler-remarks.sh <clang|gcc> <out-dir> -- <compile-command...>

Examples:
  collect-compiler-remarks.sh clang out -- clang++ -O3 -c foo.cpp -o foo.o
  collect-compiler-remarks.sh gcc out -- g++ -O3 -c foo.cpp -o foo.o
EOF
  exit 1
}

[[ $# -ge 4 ]] || usage

compiler_family="$1"
out_dir="$2"
shift 2

[[ "$1" == "--" ]] || usage
shift

mkdir -p "$out_dir"
# Resolve to an absolute path so the compiler and post-compile moves don't
# care about the caller's working directory.
out_dir_abs="$(cd "$out_dir" && pwd)"
stdout_file="$out_dir_abs/stdout.txt"
stderr_file="$out_dir_abs/stderr.txt"

case "$compiler_family" in
  clang)
    # Clang honors -foptimization-record-file=<path>, so we can pin the
    # YAML output directly into out_dir.
    extra_flags=(
      -Rpass=.*
      -Rpass-missed=.*
      -Rpass-analysis=.*
      -fsave-optimization-record
      "-foptimization-record-file=${out_dir_abs}/remarks.opt.yaml"
    )
    ;;
  gcc)
    # GCC has no flag to redirect -fsave-optimization-record output; it
    # drops <source>.opt-record.json.gz next to each source file. We move
    # any new artifacts into out_dir after the compile finishes.
    extra_flags=(
      -fopt-info
      -fopt-info-vec-missed
      -fsave-optimization-record
      -fdump-passes
    )
    ;;
  *)
    usage
    ;;
esac

cmd=("$@" "${extra_flags[@]}")

echo "Running compile command with optimization remarks:" >&2
printf '  %q' "${cmd[@]}" >&2
echo >&2

# For GCC, -fsave-optimization-record drops <source>.opt-record.json.gz next
# to each source file with no flag to redirect it. Walk the compile command,
# identify the source files, and remember their directories so we can scan
# exactly those locations after the compile. Skip known flag-value pairs
# (`-o foo.o`, `-include foo.h`, etc.) to avoid treating values as sources.
scan_dirs=()
add_scan_dir() {
  local d="$1"
  [[ -d "$d" ]] || return 0
  local abs
  abs="$(cd "$d" && pwd)" || return 0
  for existing in "${scan_dirs[@]}"; do
    [[ "$existing" == "$abs" ]] && return 0
  done
  scan_dirs+=("$abs")
}
add_scan_dir "."  # always cover CWD as a safety net

skip_next=0
for arg in "$@"; do
  if (( skip_next )); then
    skip_next=0
    continue
  fi
  case "$arg" in
    -o|-include|-isystem|-isysroot|-MT|-MF|-MQ|-MD|-MMD|-aux-info|-Xlinker|-Xpreprocessor|-Xassembler)
      skip_next=1
      ;;
    -*)
      ;;
    *.c|*.cc|*.cpp|*.cxx|*.c++|*.C|*.CPP|*.CC|*.CXX|*.cp)
      add_scan_dir "$(dirname "$arg")"
      ;;
  esac
done

pre_snapshot="$(mktemp)"
post_snapshot="$(mktemp)"
trap 'rm -f "$pre_snapshot" "$post_snapshot"' EXIT

snapshot_records() {
  local out="$1"
  : > "$out"
  if [[ "$compiler_family" == "gcc" ]]; then
    for d in "${scan_dirs[@]}"; do
      find "$d" -maxdepth 1 -type f -name '*.opt-record.json.gz' \
        -printf '%p\n' 2>/dev/null >> "$out"
    done
    sort -u "$out" -o "$out"
  fi
}

snapshot_records "$pre_snapshot"

set +e
"${cmd[@]}" >"$stdout_file" 2>"$stderr_file"
status=$?
set -e

if [[ "$compiler_family" == "gcc" ]]; then
  snapshot_records "$post_snapshot"
  moved_any=0
  while IFS= read -r new_file; do
    [[ -z "$new_file" ]] && continue
    dest="${out_dir_abs}/$(basename "$new_file")"
    # Avoid silently clobbering if two source files share a basename.
    if [[ -e "$dest" ]]; then
      dest="${out_dir_abs}/$(date +%s%N)-$(basename "$new_file")"
    fi
    mv -f "$new_file" "$dest"
    echo "moved GCC optimization record: $dest" >&2
    moved_any=1
  done < <(comm -13 "$pre_snapshot" "$post_snapshot")
  if (( ! moved_any )); then
    echo "note: no new GCC optimization-record files detected in: ${scan_dirs[*]}" >&2
  fi
fi

echo "stdout: $stdout_file" >&2
echo "stderr: $stderr_file" >&2
if [[ "$compiler_family" == "clang" ]]; then
  echo "clang remarks YAML: ${out_dir_abs}/remarks.opt.yaml" >&2
fi
echo "exit status: $status" >&2

exit "$status"
