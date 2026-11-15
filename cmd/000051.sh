# timeout=900
set -u
export JAVA_HOME="${JAVA_HOME_17_X64:-$JAVA_HOME}"; export PATH="$JAVA_HOME/bin:$PATH"
java -version 2>&1 | head -1
bash ci/prepare_android.sh && echo PREPARED
echo "=== kotlin unit tests"
(cd android && ./gradlew :app:testDebugUnitTest --console=plain 2>&1 | tail -25)
echo "=== apk"
flutter build apk --release 2>&1 | tail -15
mkdir -p "$DS_ART" && cp build/app/outputs/flutter-apk/app-release.apk "$DS_ART/directional-audio-v0.4.0-wip.apk" && ls -la "$DS_ART"
ls android/app/build/test-results/testDebugUnitTest/ 2>/dev/null | head
grep -ho 'tests="[0-9]*" skipped="[0-9]*" failures="[0-9]*"' android/app/build/test-results/testDebugUnitTest/*.xml 2>/dev/null
