# timeout=120
cd "$DS_REPO"
emu sh dumpsys media.audio_flinger 2>&1 | grep -iE -A3 "virtualizer|bass|loudness" | head -40
echo ---- conf
emu sh 'ls /vendor/etc/audio_effects* /system/etc/audio_effects* 2>/dev/null'
emu sh 'grep -iE "virtualizer|bassboost|loudness" /vendor/etc/audio_effects.xml /vendor/etc/audio_effects.conf 2>/dev/null | head -20'
