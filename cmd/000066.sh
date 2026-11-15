# timeout=600
export JAVA_HOME=$JAVA_HOME_17_X64
emu start 2>&1 | tail -3
emu install build/app/outputs/flutter-apk/app-release.apk 2>&1 | tail -2
emu logclear
emu launch 2>&1 | tail -2
sleep 4
emu ui 2>&1 | head -40
