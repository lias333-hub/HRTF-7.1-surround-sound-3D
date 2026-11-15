# timeout=400
cd "$DS_REPO"
emu sh 'am force-stop com.directionalaudio.directional_audio'; sleep 1
emu launch com.directionalaudio.directional_audio 2>&1 | tail -1; sleep 7
echo "--- start state ---"; emu ui 2>&1 | grep -E "Enable equalizer" | head -2
emu tapt 'System'; sleep 3
emu ui 2>&1 | grep -E "Enable equalizer|not being processed" | head -3
emu sh 'input swipe 540 1900 540 400 300'; sleep 1; emu sh 'input swipe 540 1900 540 400 300'; sleep 1
emu tapt 'Engine'; sleep 3
echo "--- engine screen, system eq ---"
emu ui 2>&1 | grep -E "Status|Profiles per" | head -3
emu tap 540 400; sleep 4   # the service switch
echo "--- service switch ---"
emu ui 2>&1 | grep -E "Status|Switch" | head -4
echo "--- notification ---"
emu sh 'dumpsys notification --noredact | grep -iE "pkg=com.directionalaudio|android.title|android.text" | head -6'
emu shot v04_service | tail -1
emu crash | head -5
