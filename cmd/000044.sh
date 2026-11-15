# timeout=240
PKG=com.directionalaudio.directional_audio
emu tap 540 779; sleep 1
emu tap 540 475; sleep 2
emu shot eq_dyn
echo "--- audioflinger effects (dynamics/equalizer)"
emu sh dumpsys media.audio_flinger 2>&1 | grep -i -E "dynamics|equalizer|Effect Module|7261676f" | head -12
echo "--- tools tab"
emu tap 675 2232; sleep 1
emu ui | grep -i -E "engine|device info|Tab" | head
