# timeout=300
export JAVA_HOME=$JAVA_HOME_17_X64
emu launch com.directionalaudio.directional_audio 2>&1 | tail -2
sleep 5
emu ui 2>&1 | head -30
