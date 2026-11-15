# timeout=520
dsync main >/dev/null && export JAVA_HOME=${JAVA_HOME_17_X64:-$JAVA_HOME}; flutter build apk --release > /tmp/build.log 2>&1; echo "build rc=$?"; grep -E "BUILD|Built |Compilation" /tmp/build.log | head; grep -h "error:" /tmp/kotlin-daemon*.log 2>/dev/null | tail -3; cp build/app/outputs/flutter-apk/app-release.apk "$DS_ART"/directional-audio-0.1.0.apk && ls -la "$DS_ART"
