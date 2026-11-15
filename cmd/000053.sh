# timeout=400
cd "$DS_REPO"
emu sh 'am force-stop com.directionalaudio.directional_audio'; sleep 1
emu launch com.directionalaudio.directional_audio 2>&1 | tail -1; sleep 7
echo "--- system equalizer on ---"
emu tapt 'System'; sleep 1
emu ui 2>&1 | grep -iE "Switch" | head -3
emu tap 110 478; sleep 3
emu ui 2>&1 | grep -iE "Enable equalizer|not being|Retry|control" | head -6
emu shot v04_sys_on | tail -1
echo "--- scroll down and open the engine screen ---"
emu sh 'input swipe 540 1900 540 400 300'; sleep 1; emu sh 'input swipe 540 1900 540 400 300'; sleep 1
emu tapt 'Engine'; sleep 3
emu ui 2>&1 | grep -iE "Profile:|Profiles per|Speaker|Bass|Flat|None yet|Lock|not being|Equalizer|running|stopped|System" | head -14
emu shot v04_engine2 | tail -1
echo "--- start the service ---"
emu tapt 'Keep the engine' 2>&1 | tail -1
emu ui 2>&1 | grep -iE "Switch" | head -2
