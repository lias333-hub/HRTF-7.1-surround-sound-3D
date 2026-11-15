# timeout=700
pwd; git log --oneline | head -1; flutter pub get >/dev/null 2>&1; flutter analyze 2>&1 | tail -30; flutter test 2>&1 | tail -40
