#!/usr/bin/env bash
# Builds and runs the C++ core tests on the host, with several compilers and with sanitizers.
# Usage: bash ci/cpp_tests.sh            (uses g++ and clang++ when available)
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
rc=0
run() {  # name compiler build-type extra-flags
  local name=$1 cxx=$2 type=$3 flags=$4
  if ! command -v "$cxx" >/dev/null 2>&1; then echo "[skip] $name: $cxx not found"; return; fi
  echo "=== $name ($cxx, $type $flags)"
  if ! cmake -S native/cpp -B "$tmp/$name" -DCMAKE_CXX_COMPILER="$cxx" -DCMAKE_BUILD_TYPE="$type" \
    -DCMAKE_CXX_FLAGS="$flags" >/dev/null 2>&1; then
    # e.g. a clang install without the sanitizer runtime: skip loudly instead of failing the whole run
    if [[ "$flags" == *sanitize* ]]; then echo "[skip] $name: this compiler cannot build with sanitizers here"; return; fi
    echo "cmake failed for $name"; rc=1; return
  fi
  cmake --build "$tmp/$name" -j2 2>&1 | grep -E "warning|error" || true
  if ! "$tmp/$name/da_tests"; then rc=1; fi
}
run gcc-release g++ Release ""
run gcc-sanitize g++ Debug "-fsanitize=address,undefined -fno-sanitize-recover=undefined -g"
run clang-release clang++ Release ""
run clang-sanitize clang++ Debug "-fsanitize=address,undefined -fno-sanitize-recover=undefined -g"
exit $rc
