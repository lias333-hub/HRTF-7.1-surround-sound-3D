# timeout=900
export PATH=$PWD/ci/devshell/bin:$PATH
emu start 2>&1 | tail -5
emu install $DS_ART/directional-audio-0.5.0.apk 2>&1 | tail -3
emu launch com.directionalaudio.directional_audio 2>&1 | tail -2
sleep 4
emu tapt 'Tools' 2>&1 | tail -2
sleep 2
emu ui 2>&1 | head -40
