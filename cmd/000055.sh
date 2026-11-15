# timeout=300
cd "$DS_REPO"
emu key BACK; sleep 1
emu tapt 'Enable equalizer'; sleep 3
echo "--- EQ tab after enabling System equalizer ---"
emu ui 2>&1 | grep -E "Enable equalizer|not being processed|Retry" | head -4
emu sh 'input swipe 540 1900 540 400 300'; sleep 1; emu sh 'input swipe 540 1900 540 400 300'; sleep 1
emu tapt 'Engine'; sleep 3
emu ui 2>&1 | grep -E "Status" | head -2
emu shot v04_sys_engine | tail -1
echo "--- toggle EQ off/on while service runs, look at the notification text ---"
emu sh 'dumpsys notification --noredact | grep -E "android.text" | head -2'
emu crash | head -5
