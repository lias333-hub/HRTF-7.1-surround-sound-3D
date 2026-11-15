# timeout=300
cd "$DS_REPO"
emu key BACK; sleep 2
emu sh 'input swipe 540 500 540 1900 300'; sleep 1; emu sh 'input swipe 540 500 540 1900 300'; sleep 1
emu tapt 'Enable equalizer'; sleep 3
echo "--- EQ tab after enabling ---"
emu ui 2>&1 | grep -E "Enable equalizer|not being processed|Retry now" | head -4
emu shot v04_sys_on3 | tail -1
emu sh 'input swipe 540 1900 540 400 300'; sleep 1; emu sh 'input swipe 540 1900 540 400 300'; sleep 1
emu tapt 'Engine'; sleep 3
emu ui 2>&1 | grep -E "Status" | head -2
emu sh 'dumpsys notification --noredact | grep -E "android.text" | head -1'
emu crash | head -5
