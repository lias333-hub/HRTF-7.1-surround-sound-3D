# timeout=1500
export JAVA_HOME=$JAVA_HOME_17_X64
export PATH=$PWD/ci/devshell/bin:$PATH
emu stop >/dev/null 2>&1
git fetch -q origin main && git reset -q --hard origin/main && git log --oneline | head -1
rm -rf build android/app/build android/app/.cxx
bash ci/prepare_android.sh 2>&1 | tail -1
flutter analyze 2>&1 | tail -2
flutter test 2>&1 | tail -2
(cd android && ./gradlew :app:testDebugUnitTest --console=plain 2>&1 | grep -E "BUILD|FAIL|tests completed")
flutter build apk --release 2>&1 | tail -2
APK=build/app/outputs/flutter-apk/app-release.apk
unzip -l $APK | grep libdacore; bash ci/check_native_libs.sh $APK; bash ci/check_signing.sh $APK
mkdir -p $DS_ART && cp $APK $DS_ART/directional-audio-0.5.0.apk && sha256sum $DS_ART/directional-audio-0.5.0.apk
