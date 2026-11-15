# timeout=300
export JAVA_HOME=$JAVA_HOME_17_X64
emu tap 540 470; sleep 3
emu tap 675 2232; sleep 2
emu ui 2>&1 | head -20
