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
cp native/*.kt "$pkg_dir/"
cp native/AndroidManifest.xml android/app/src/main/AndroidManifest.xml

# JVM unit tests for the pure Kotlin logic (run with: cd android && ./gradlew :app:testDebugUnitTest).
test_dir=android/app/src/test/kotlin/com/directionalaudio/directional_audio
mkdir -p "$test_dir"
cp native/test/*.kt "$test_dir/"
if ! grep -q "junit:junit" android/app/build.gradle; then
  printf "\ndependencies {\n    testImplementation 'junit:junit:4.13.2'\n}\n" >> android/app/build.gradle
fi

flutter pub get
