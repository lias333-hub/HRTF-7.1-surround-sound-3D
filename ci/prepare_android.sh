#!/usr/bin/env bash
# Generates the Android host project (not committed) and overlays our native files. Idempotent.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -d android ]; then
  tmp=$(mktemp -d)
  flutter create "$tmp/app" --platforms android --project-name directional_audio \
    --org com.directionalaudio >/dev/null
  cp -r "$tmp/app/android" android
  rm -rf "$tmp"
fi

pkg_dir=android/app/src/main/kotlin/com/directionalaudio/directional_audio
mkdir -p "$pkg_dir"
cp native/MainActivity.kt "$pkg_dir/MainActivity.kt"
cp native/AndroidManifest.xml android/app/src/main/AndroidManifest.xml

flutter pub get
