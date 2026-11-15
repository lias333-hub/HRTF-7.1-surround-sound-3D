# timeout=700
git fetch -q origin main && git reset -q --hard origin/main; git log --oneline | head -1; flutter test 2>&1 | grep -E "^::error|tests passed|All tests|failed|Expected|Actual" | head -30
