# timeout=600
cd "$DS_REPO"
emu start 2>&1 | tail -1
emu install build/app/outputs/flutter-apk/app-release.apk 2>&1 | tail -1
emu logclear >/dev/null 2>&1
emu launch com.directionalaudio.directional_audio 2>&1 | tail -1
sleep 7
echo "--- EQ tab, default (system) ---"; emu ui 2>&1 | grep -iE "Output|Playing|assign|Lock|bypass|not being" | head -12
emu shot v04_eq_system | tail -1
emu tapt 'Dynamics' ; sleep 1
emu tap 110 478; sleep 3
echo "--- EQ on (dynamics) ---"; emu ui 2>&1 | grep -iE "Playing|assign|Lock|bypass|not being|Dynamics" | head -12
emu shot v04_eq_dyn_on | tail -1
emu tapt 'Use this profile for this output'; sleep 2
echo "--- after assign ---"; emu ui 2>&1 | grep -iE "Profile for this|Remove|No profile" | head
emu shot v04_assigned | tail -1
echo "--- engine screen ---"
emu tapt 'Engine & background'; sleep 3
emu ui 2>&1 | grep -iE "Profile:|Profiles per|Speaker|Bass|Flat|Lock|bypass|not being|Equalizer" | head -12
emu shot v04_engine | tail -1
emu key BACK; sleep 1
echo "--- force-stop and relaunch: the table must survive ---"
emu sh 'am force-stop com.directionalaudio.directional_audio'; sleep 1
emu launch com.directionalaudio.directional_audio 2>&1 | tail -1; sleep 7
emu tapt 'Engine & background' ; sleep 3
emu ui 2>&1 | grep -iE "Profiles per|Speaker|Flat|None yet|Profile:" | head -8
emu shot v04_after_restart | tail -1
emu crash | head -8
emu sh 'logcat -d -s AndroidRuntime:E | tail -5'
