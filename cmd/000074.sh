# timeout=900
pwd
git fetch -q origin main && git reset -q --hard origin/main && git log --oneline | head -1
export JAVA_HOME=$JAVA_HOME_17_X64
echo "--- tools"; which cmake g++ clang++ python3 sdkmanager 2>&1 | head; echo "ANDROID_HOME=${ANDROID_HOME:-} NDK=${ANDROID_NDK_HOME:-}${ANDROID_NDK_LATEST_HOME:-}"
ls ${ANDROID_HOME:-/usr/local/lib/android/sdk}/ndk 2>&1 | head; ls ${ANDROID_HOME:-/usr/local/lib/android/sdk}/cmake 2>&1 | head
echo "--- prepare"; bash ci/prepare_android.sh 2>&1 | tail -3
echo "--- cpp tests"; bash ci/cpp_tests.sh 2>&1 | grep -E "^===|checks|skip|FAIL|error" 
echo "--- analyze"; flutter analyze 2>&1 | tail -15
echo "--- flutter test"; flutter test 2>&1 | tail -25
