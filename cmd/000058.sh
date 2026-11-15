# timeout=300
cd "$DS_REPO"
emu key BACK; sleep 2
emu sh 'input swipe 540 500 540 1900 300'; sleep 1; emu sh 'input swipe 540 500 540 1900 300'; sleep 1
emu tap 200 674; sleep 3
echo "--- EQ tab on System type ---"
emu ui 2>&1 | grep -E "Enable equalizer|not being processed|Retry now|RadioButton" | head -6
emu shot v04_sys_type | tail -1
emu sh 'input swipe 540 1900 540 400 300'; sleep 1; emu sh 'input swipe 540 1900 540 400 300'; sleep 1
emu tapt 'Engine'; sleep 3
emu ui 2>&1 | grep -E "Status" | head -2
emu crash | head -5
