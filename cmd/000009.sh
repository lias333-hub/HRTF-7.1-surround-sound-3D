# timeout=400
export JAVA_HOME=${JAVA_HOME_17_X64:-$JAVA_HOME}; cd android && ./gradlew :app:compileReleaseKotlin --console=plain 2>&1 | grep -E "^e: |^w: .*MainActivity|error:" | head -20
