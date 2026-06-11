#!/usr/bin/env bash
# Wraps a single compile command and collects optimization remarks into
# <out-dir>: Clang YAML remarks plus -Rpass diagnostics on stderr, or the
# GCC JSON optimization record plus -fopt-info diagnostics on stderr.
# Safe to execute; it only adds remark flags to the given compile command.
# Requires bash >= 4.4 and GNU coreutils (Linux).
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  collect-compiler-remarks.sh <clang|gcc> <out-dir> -- <compile-command...>

Examples:
  collect-compiler-remarks.sh clang out -- clang++ -O3 -c foo.cpp -o foo.o
  collect-compiler-remarks.sh gcc out -- g++ -O3 -c foo.cpp -o foo.o

Notes:
  Wrap one translation unit per invocation; with multiple TUs the Clang
  record file is rewritten per TU and only the last survives.
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
# Resolve to an absolute path so the compiler flags below don't care about
# the caller's working directory.
out_dir_abs="$(cd "$out_dir" && pwd)"
stdout_file="$out_dir_abs/stdout.txt"
stderr_file="$out_dir_abs/stderr.txt"

case "$compiler_family" in
  clang)
    # Clang honors -foptimization-record-file=<path> (which implies
    # -fsave-optimization-record), so the YAML lands directly in out_dir.
    # The -Rpass* patterns are POSIX regexes; '.*' selects all passes.
    extra_flags=(
      '-Rpass=.*'
      '-Rpass-missed=.*'
      '-Rpass-analysis=.*'
      "-foptimization-record-file=${out_dir_abs}/remarks.opt.yaml"
    )
    ;;
  gcc)
    # GCC writes the record where its auxiliary dump outputs go: next to
    # the -o object file, named after the dump base (e.g. -c src/foo.cpp
    # -o build/foo.o => build/foo.cpp.opt-record.json.gz) — NOT next to
    # the source file. -dumpdir redirects all aux outputs; the trailing
    # slash is significant. -fopt-info and -fopt-info-vec-missed combine
    # on stderr (only their '=file' forms conflict with each other).
    extra_flags=(
      -fopt-info
      -fopt-info-vec-missed
      -fsave-optimization-record
      -dumpdir "${out_dir_abs}/"
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

# Remove stale records so a reused out-dir can't report an old record as
# the result of this compile (out_dir is owned by this script).
rm -f "$out_dir_abs"/*.opt-record.json.gz

set +e
"${cmd[@]}" >"$stdout_file" 2>"$stderr_file"
status=$?
set -e

if [[ "$compiler_family" == "gcc" ]]; then
  shopt -s nullglob
  records=("$out_dir_abs"/*.opt-record.json.gz)
  shopt -u nullglob
  if (( ${#records[@]} )); then
    printf 'GCC optimization record: %s\n' "${records[@]}" >&2
  elif (( status == 0 )); then
    echo "note: no .opt-record.json.gz appeared in $out_dir_abs;" >&2
    echo "      check that the wrapped command actually compiles a TU (-c)" >&2
  fi
fi

echo "stdout: $stdout_file" >&2
echo "stderr: $stderr_file" >&2
if [[ "$compiler_family" == "clang" ]]; then
  echo "clang remarks YAML: ${out_dir_abs}/remarks.opt.yaml" >&2
fi
echo "exit status: $status" >&2

exit "$status"
