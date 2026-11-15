# timeout=600
dsync >/dev/null && cd "$DS_REPO" && flutter analyze 2>&1 | tail -2 && flutter test 2>&1 | grep -E "^::error|All tests|passed|failed" | tail -8
