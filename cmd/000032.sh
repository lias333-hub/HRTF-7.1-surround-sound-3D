# timeout=60
cd "$DS_REPO"; emu sh dumpsys media.audio_flinger 2>&1 | grep -iE "TYPE: (0bed4300|0634f220|37cc2c00|fe3199be)" | sort -u
