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

# Fixed TEST signing key. Without it every fresh CI box generates its own debug key, so an update APK
# cannot be installed over the previous one. The key is public (the repo is public): test builds only,
# NEVER for a real release (that gets a secret key later). Set DA_KEEP_LOCAL_KEY=1 to keep your own debug key.
if [ -z "${DA_KEEP_LOCAL_KEY:-}" ]; then
  mkdir -p "$HOME/.android"
  cp ci/test-signing/debug.keystore "$HOME/.android/debug.keystore"
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

# C++ core: copied into the Android module and built by CMake for every ABI Flutter targets (armeabi-v7a,
# arm64-v8a, x86_64). Copied fresh each time so deleted source files do not linger. Idempotent gradle patch.
rm -rf android/app/src/main/cpp
mkdir -p android/app/src/main/cpp
cp -r native/cpp/. android/app/src/main/cpp/
if ! grep -q "src/main/cpp/CMakeLists.txt" android/app/build.gradle; then
  cat >> android/app/build.gradle <<'GRADLE'

// Directional Audio: build the C++ core (libdacore.so) with the Android NDK.
android {
    externalNativeBuild {
        cmake {
            path "src/main/cpp/CMakeLists.txt"
        }
    }
}
GRADLE
fi

flutter pub get
