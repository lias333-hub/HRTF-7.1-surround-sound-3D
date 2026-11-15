# timeout=520
export JAVA_HOME=${JAVA_HOME_17_X64:-$JAVA_HOME}; flutter build apk --release > /tmp/build.log 2>&1; echo "build rc=$?"; grep -E "^e: |^w: .*MainActivity|BUILD|Built |Compilation" /tmp/build.log | head -20; cp build/app/outputs/flutter-apk/app-release.apk "$DS_ART"/directional-audio-0.1.0.apk && ls -la "$DS_ART"
