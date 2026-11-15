# timeout=960
set -e
export JAVA_HOME=$JAVA_HOME_17_X64
echo "--- kotlin unit tests"
(cd android && ./gradlew :app:testDebugUnitTest --console=plain 2>&1 | tail -25) || true
python3 - <<'PY'
import glob,re
tot=fail=0
for f in glob.glob('build/app/test-results/testDebugUnitTest/*.xml'):
    s=open(f).read()
    m=re.search(r'tests="(\d+)" skipped="(\d+)" failures="(\d+)" errors="(\d+)"',s)
    print(f.split('/')[-1],m.groups())
PY
echo "--- release build"
flutter build apk --release 2>&1 | tail -6
bash ci/check_signing.sh build/app/outputs/flutter-apk/app-release.apk
cp build/app/outputs/flutter-apk/app-release.apk $DS_ART/directional-audio-v0.4.1.apk
ls -l $DS_ART
