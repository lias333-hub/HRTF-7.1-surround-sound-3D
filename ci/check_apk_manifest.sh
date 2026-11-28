#!/usr/bin/env bash
# Fails unless the built APK declares what we decided (AU-31): minSdk 21 and exactly the permissions we expect.
# A new permission is a product decision: add it to the list below on purpose, in the same commit.
# Usage: bash ci/check_apk_manifest.sh path/to/app.apk
set -euo pipefail
apk=${1:?usage: check_apk_manifest.sh app.apk}

sdk_root="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [ -z "$sdk_root" ] || [ ! -d "$sdk_root/build-tools" ]; then
  echo "no Android SDK build-tools (ANDROID_HOME=${ANDROID_HOME:-unset}): cannot read the APK manifest" >&2
  exit 2
fi
aapt=$(ls -1d "$sdk_root"/build-tools/*/aapt 2>/dev/null | sort -V | tail -1 || true)
if [ -z "$aapt" ]; then
  echo "no aapt in $sdk_root/build-tools" >&2
  exit 2
fi
badging=$("$aapt" dump badging "$apk")

rc=0
min=$(printf '%s\n' "$badging" | sed -n "s/^sdkVersion:'\([0-9]*\)'.*/\1/p" | head -1)
if [ "$min" = "21" ]; then
  echo "ok: minSdk $min"
else
  echo "MINSDK MISMATCH: got '${min:-none}', expected 21"
  rc=1
fi

expected="android.permission.FOREGROUND_SERVICE
android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK
android.permission.MODIFY_AUDIO_SETTINGS
android.permission.POST_NOTIFICATIONS
android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS"
want=$(printf '%s\n' "$expected" | sort -u)
got=$(printf '%s\n' "$badging" | sed -n "s/^uses-permission:.*name='\([^']*\)'.*/\1/p" | sort -u)
if [ "$got" = "$want" ]; then
  echo "ok: permissions are exactly the expected $(printf '%s\n' "$want" | wc -l)"
else
  echo "PERMISSIONS MISMATCH (< expected, > found)"
  diff <(printf '%s\n' "$want") <(printf '%s\n' "$got") || true
  rc=1
fi
exit $rc
