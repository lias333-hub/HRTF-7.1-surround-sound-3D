# timeout=300
cd "$DS_REPO" && emu install build/app/outputs/flutter-apk/app-release.apk 2>&1 | tail -3; emu launch com.directionalaudio.directional_audio 2>&1 | tail -2; sleep 6; emu shot v02_eq_en; emu ui 2>&1 | head -40
