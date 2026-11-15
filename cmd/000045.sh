# timeout=240
PKG=com.directionalaudio.directional_audio
emu tap 540 663; sleep 2
emu shot engine_off
emu ui | grep -E "desc='[A-Za-z]" | head -14
echo "--- toggle service on"
emu tap 540 420; sleep 4
emu shot engine_on
emu sh dumpsys activity services $PKG 2>&1 | grep -E "ServiceRecord|isForeground|foregroundServiceType|startRequested" | head -6
emu sh dumpsys notification --noredact 2>&1 | grep -E "pkg=$PKG|tickerText|android.title|android.text" | head -6
echo "--- crashes"
emu crash 2>&1 | head -20
echo "--- toggle service off"
emu tap 540 420; sleep 3
emu sh dumpsys activity services $PKG 2>&1 | grep -c ServiceRecord
