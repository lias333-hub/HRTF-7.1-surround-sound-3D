#!/usr/bin/env bash
# Fails when the APK does not carry the C++ core for every ABI we promise (32-bit ARM first, then 64-bit ARM).
# Usage: bash ci/check_native_libs.sh path/to/app.apk
set -euo pipefail
apk=${1:?usage: check_native_libs.sh app.apk}
list=$(unzip -l "$apk")
rc=0
for abi in armeabi-v7a arm64-v8a; do
  if echo "$list" | grep -q "lib/$abi/libdacore.so"; then
    echo "ok: lib/$abi/libdacore.so"
  else
    echo "MISSING: lib/$abi/libdacore.so in $apk"
    rc=1
  fi
done
exit $rc
