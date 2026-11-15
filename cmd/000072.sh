# timeout=960
export JAVA_HOME=$JAVA_HOME_17_X64
git fetch -q origin main && git reset -q --hard origin/main
git log --oneline | head -1
bash ci/prepare_android.sh >/dev/null 2>&1
flutter analyze 2>&1 | tail -3
flutter test 2>&1 | tail -2
(cd android && ./gradlew :app:testDebugUnitTest --console=plain 2>&1 | grep -E "BUILD|FAILED|error:|e: " | head)
python3 - <<'PY'
import glob,re
t=0
for f in glob.glob('build/app/test-results/testDebugUnitTest/*.xml'):
    m=re.search(r'tests="(\d+)" skipped="(\d+)" failures="(\d+)" errors="(\d+)"',open(f).read()); print(f.split('.')[-2],m.groups())
PY
flutter build apk --release 2>&1 | tail -2
bash ci/check_signing.sh build/app/outputs/flutter-apk/app-release.apk
cp build/app/outputs/flutter-apk/app-release.apk $DS_ART/directional-audio-v0.4.1.apk
sha256sum $DS_ART/directional-audio-v0.4.1.apk; ls -l $DS_ART/directional-audio-v0.4.1.apk
