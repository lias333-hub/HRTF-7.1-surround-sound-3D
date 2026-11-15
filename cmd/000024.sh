# timeout=600
dsync && cd "$DS_REPO" && flutter analyze 2>&1 | tail -3 && flutter test 2>&1 | tail -6
