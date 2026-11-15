# timeout=600
cd "$DS_REPO" && git log -1 --format="%h %s" && flutter analyze 2>&1 | tail -40 && flutter test 2>&1 | tail -60
