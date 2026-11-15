# timeout=600
cd "$DS_REPO"
emu start 2>&1 | tail -1
emu install build/app/outputs/flutter-apk/app-release.apk 2>&1 | tail -1
emu launch com.directionalaudio.directional_audio 2>&1 | tail -1
sleep 7
emu tap 945 2232; sleep 2
emu tap 540 430; sleep 2
emu tap 540 1675; sleep 3
emu tap 405 2232; sleep 2
emu tap 540 432; sleep 3
emu shot v020_ar_info
emu key BACK; sleep 1
emu crash | head -5
