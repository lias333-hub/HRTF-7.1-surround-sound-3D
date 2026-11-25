#!/usr/bin/env bash
# Usage: ci/check_signing.sh app-release.apk
# Fails unless the APK is signed with the fixed test key (so updates install over each other).
set -euo pipefail
expected="37:40:E5:44:BE:09:41:E8:32:11:C2:A5:6B:61:91:7A:1C:D1:E8:3F:A3:22:9B:8B:90:46:C8:2D:E7:BB:8B:27"
got=$(keytool -printcert -jarfile "$1" | sed -n 's/^[[:space:]]*SHA256: //p' | head -1)
if [ "$got" != "$expected" ]; then
  echo "SIGNING MISMATCH: $got (expected $expected)" >&2
  exit 1
fi
echo "signing OK: $got"
