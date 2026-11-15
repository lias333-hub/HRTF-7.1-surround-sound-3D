# timeout=300
export JAVA_HOME=$JAVA_HOME_17_X64
emu tap 540 660; sleep 2
# swipe up to bring the log card into view
emu sh 'input swipe 540 1900 540 500 400'; sleep 1
emu sh 'input swipe 540 1900 540 500 400'; sleep 1
emu shot log1 2>&1 | tail -1
emu ui 2>&1 | grep -i "log\|Copy\|Clear\|Refresh\|process\|\[svc\]\|\[eq\]" | head -20
