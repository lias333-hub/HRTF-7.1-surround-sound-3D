# timeout=120
cd "$DS_REPO" && flutter test 2>&1 | grep -E "^::error|passed|failed|All tests" | head
