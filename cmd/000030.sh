# timeout=240
cd "$DS_REPO"
emu tap 405 2232; sleep 2; emu shot v02_fx_en
emu tap 675 2232; sleep 2; emu shot v02_tools_en
emu tapt 'Device info' ; sleep 3; emu shot v02_info_en
emu key BACK; sleep 1
emu tap 945 2232; sleep 2; emu shot v02_settings_en
emu tapt 'Language'; sleep 2; emu shot v02_langsheet_en
emu ui | head -30
emu crash | head -20
