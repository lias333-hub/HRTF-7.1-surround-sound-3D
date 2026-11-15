# timeout=900
cd "$DS_REPO" && flutter build apk --release 2>&1 | tail -25; ls -la build/app/outputs/flutter-apk/ 2>&1 | tail -5; grep -h "error:" /tmp/kotlin-daemon*.log 2>/dev/null | head -20
