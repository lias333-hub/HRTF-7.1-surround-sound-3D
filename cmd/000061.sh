# timeout=900
set -u
git fetch -q origin main && git reset -q --hard origin/main && git log --oneline | head -1
export JAVA_HOME="${JAVA_HOME_17_X64:-$JAVA_HOME}"; export PATH="$JAVA_HOME/bin:$PATH"
bash ci/prepare_android.sh >/dev/null && echo PREPARED
flutter analyze 2>&1 | tail -2
flutter test 2>&1 | grep -E "tests passed|failed" | tail -2
(cd android && ./gradlew :app:testDebugUnitTest --console=plain 2>&1 | grep -E "BUILD|FAILED" | head -3)
flutter build apk --release 2>&1 | grep -E "Built|Error|error" | head -3
rm -f "$DS_ART"/*.apk "$DS_ART"/*.png 2>/dev/null; mkdir -p "$DS_ART"
cp build/app/outputs/flutter-apk/app-release.apk "$DS_ART/directional-audio-v0.4.0.apk"
sha256sum "$DS_ART/directional-audio-v0.4.0.apk" | cut -c1-16; ls -la "$DS_ART" | tail -1
