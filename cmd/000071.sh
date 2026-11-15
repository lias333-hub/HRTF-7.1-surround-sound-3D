# timeout=300
export JAVA_HOME=$JAVA_HOME_17_X64
emu launch com.directionalaudio.directional_audio 2>&1 | tail -1; sleep 5
emu tap 675 2232; sleep 2
emu tap 540 660; sleep 2
emu sh 'input swipe 540 1900 540 500 400'; sleep 1
emu sh 'input swipe 540 1900 540 500 400'; sleep 1
emu ui 2>&1 | grep -A0 "TextView\|View text=\"11-" | grep "11-" | sed 's/\\n/\n/g' | head -40
