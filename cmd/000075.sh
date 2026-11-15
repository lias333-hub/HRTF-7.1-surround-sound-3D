# timeout=1500
export JAVA_HOME=$JAVA_HOME_17_X64
grep -n "ndkVersion\|minSdk\|compileSdk" android/app/build.gradle | head
echo "--- junit"; (cd android && ./gradlew :app:testDebugUnitTest --console=plain 2>&1 | tail -25)
echo "--- release build"; flutter build apk --release 2>&1 | tail -40
echo "--- libs"; bash ci/check_native_libs.sh build/app/outputs/flutter-apk/app-release.apk
unzip -l build/app/outputs/flutter-apk/app-release.apk | grep -E "libdacore|libflutter|libapp"
bash ci/check_signing.sh build/app/outputs/flutter-apk/app-release.apk
mkdir -p $DS_ART && cp build/app/outputs/flutter-apk/app-release.apk $DS_ART/directional-audio-0.5.0.apk && ls -la $DS_ART
