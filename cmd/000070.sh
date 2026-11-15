# timeout=300
export JAVA_HOME=$JAVA_HOME_17_X64
P=com.directionalaudio.directional_audio
emu sh 'input swipe 540 600 540 2000 300'; sleep 1
emu sh 'input swipe 540 600 540 2000 300'; sleep 1
emu ui 2>&1 | grep -i "Switch" | head -3
emu tap 540 420; sleep 3     # service switch (top card)
echo "pid before: $(emu sh "pidof $P" 2>&1 | tail -1)"
emu sh "su 0 kill -9 \$(pidof $P)" 2>&1 | tail -2
sleep 1
echo "pid right after kill: $(emu sh "pidof $P" 2>&1 | tail -1)"
sleep 8
echo "pid 8s later: $(emu sh "pidof $P" 2>&1 | tail -1)"
emu sh "dumpsys activity services $P | grep -i 'ServiceRecord\|isForeground' | head -4" 2>&1 | tail -5
