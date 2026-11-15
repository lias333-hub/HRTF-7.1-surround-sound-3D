# timeout=600
export PATH=$PWD/ci/devshell/bin:$PATH
APK=build/app/outputs/flutter-apk/app-release.apk
emu install $APK 2>&1 | tail -3
emu logclear
emu launch com.directionalaudio.directional_audio 2>&1 | tail -2
sleep 5
emu tapt 'Tools' 2>&1 | tail -2
sleep 2
emu swipe 540 2000 540 500 400; sleep 1
emu ui 2>&1 | grep -i -E "speed|core|run test|Run|neon|abis" | head
