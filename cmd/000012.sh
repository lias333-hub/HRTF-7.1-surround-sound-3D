# timeout=400
export JAVA_HOME=${JAVA_HOME_17_X64:-$JAVA_HOME}; cd android && ./gradlew :app:compileReleaseKotlin -Pkotlin.compiler.execution.strategy=in-process --console=plain 2>&1 | grep -E "^e: |^w: |error:" | head -20; echo === DAEMON LOGS; ls /tmp/kotlin-daemon* ~/.kotlin 2>/dev/null | head; grep -h -E "^e: |error:" /tmp/kotlin-daemon*.log 2>/dev/null | head -10
