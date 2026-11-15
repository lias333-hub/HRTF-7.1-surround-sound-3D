# timeout=240
emu key BACK; sleep 1
emu tap 945 2232; sleep 1
emu tapt 'Language'; sleep 1
emu tapt 'العربية'; sleep 2
emu ui | grep -E "desc='" | head -12
emu tap 675 2232; sleep 1
emu ui | grep -E "desc='" | head -8
