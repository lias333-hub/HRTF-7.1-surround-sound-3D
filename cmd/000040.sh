# timeout=800
flutter build apk --release 2>&1 | tail -40; ls -la build/app/outputs/flutter-apk/ 2>&1; mkdir -p "$DS_ART" && cp build/app/outputs/flutter-apk/app-release.apk "$DS_ART/directional-audio-v0.3.0.apk" 2>&1; echo "--- kotlin log"; grep -h -E "^e: |error:" /tmp/kotlin-daemon*.log 2>/dev/null | head -30
