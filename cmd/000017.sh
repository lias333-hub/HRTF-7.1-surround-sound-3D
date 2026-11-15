# timeout=560
flutter build apk --release > /tmp/build.log 2>&1; echo "build rc=$?"; grep -E "Built |BUILD" /tmp/build.log | head -3; APK=build/app/outputs/flutter-apk/app-release.apk; P=$(emu pkg $APK); echo "pkg=$P"; emu install $APK; emu logclear; emu launch $P; sleep 8; emu shot app_ar; emu status | tail -1
