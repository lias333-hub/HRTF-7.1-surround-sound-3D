# timeout=240
APK=build/app/outputs/flutter-apk/app-release.apk
PKG=com.directionalaudio.directional_audio
emu install $APK 2>&1 | tail -2
emu logclear
emu launch $PKG 2>&1 | tail -1
sleep 5
emu shot eq_en
emu ui | head -40
