# timeout=300
cd "$DS_REPO" && flutter test 2>&1 | grep -v "^✅" | grep -v "^$" | head -70
