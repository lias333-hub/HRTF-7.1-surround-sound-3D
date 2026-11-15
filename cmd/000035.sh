# timeout=600
cd "$DS_REPO"
emu start 2>&1 | tail -2
emu install build/app/outputs/flutter-apk/app-release.apk 2>&1 | tail -1
emu launch com.directionalaudio.directional_audio 2>&1 | tail -1
sleep 7
emu tap 675 2232; sleep 2
emu tapt 'Device info'; sleep 3; emu shot final_info_en
emu key BACK; sleep 1
emu tap 945 2232; sleep 2
emu tap 540 430; sleep 2
emu tap 540 1675; sleep 3
emu shot final_ar_settings
emu tap 945 2232; sleep 2; emu shot final_ar_eq
emu tap 110 478; sleep 3; emu shot final_ar_eq_on
emu tap 675 2232; sleep 2; emu shot final_ar_fx
emu tap 405 2232; sleep 2; emu shot final_ar_tools
emu tap 540 432; sleep 3; emu shot final_ar_info
emu key BACK; sleep 1
emu crash | head -10
