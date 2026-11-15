# timeout=900
cd "$DS_REPO" && git log -1 --format="%h %s" && flutter analyze 2>&1 | tail -2 && flutter test 2>&1 | tail -2 && flutter build apk --release 2>&1 | tail -3; grep -h "error:" /tmp/kotlin-daemon*.log 2>/dev/null | head; ls -la build/app/outputs/flutter-apk/*.apk
