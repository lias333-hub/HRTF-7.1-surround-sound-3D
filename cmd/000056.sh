# timeout=300
cd "$DS_REPO"
emu launch com.directionalaudio.directional_audio 2>&1 | tail -1; sleep 4
emu tap 135 2232; sleep 2
emu tapt 'Enable equalizer'; sleep 3
echo "--- EQ tab after enabling the System equalizer ---"
emu ui 2>&1 | grep -E "Enable equalizer|not being processed|Retry now" | head -4
emu shot v04_sys_on2 | tail -1
emu sh 'input swipe 540 1900 540 400 300'; sleep 1; emu sh 'input swipe 540 1900 540 400 300'; sleep 1
emu tapt 'Engine'; sleep 3
emu ui 2>&1 | grep -E "Status" | head -2
emu crash | head -5
