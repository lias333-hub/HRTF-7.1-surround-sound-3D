# timeout=600
export JAVA_HOME=$JAVA_HOME_17_X64
git fetch -q origin main && git reset -q --hard origin/main
bash ci/prepare_android.sh >/dev/null 2>&1
(cd android && ./gradlew :app:testDebugUnitTest --console=plain 2>&1 | tail -8)
python3 - <<'PY'
import glob,re
for f in glob.glob('build/app/test-results/testDebugUnitTest/*.xml'):
    s=open(f).read()
    m=re.search(r'tests="(\d+)" skipped="(\d+)" failures="(\d+)" errors="(\d+)"',s)
    print(f.split('/')[-1],m.groups())
PY
