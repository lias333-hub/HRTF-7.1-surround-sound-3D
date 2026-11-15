# timeout=400
export JAVA_HOME=${JAVA_HOME_17_X64:-$JAVA_HOME}; grep -n -i -E "MainActivity|^e:|warning:|error" /tmp/build.log | head -20; echo === GRADLE; cd android && ./gradlew :app:compileReleaseKotlin --console=plain --info 2>&1 | grep -E "^e: |MainActivity|Unresolved|Expecting|Unsupported|Kotlin" | head -30
