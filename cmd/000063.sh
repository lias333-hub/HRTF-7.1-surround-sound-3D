# timeout=840
set -e
export JAVA_HOME=$JAVA_HOME_17_X64
git fetch -q origin main && git reset -q --hard origin/main
git log --oneline | head -1
bash ci/prepare_android.sh >/dev/null 2>&1
echo "--- keystore in place:"; keytool -list -keystore ~/.android/debug.keystore -storepass android 2>/dev/null | grep -i "androiddebugkey\|Certificate fingerprint" | head -2
echo "--- analyze"; flutter analyze 2>&1 | tail -15
echo "--- flutter test"; flutter test 2>&1 | tail -15
