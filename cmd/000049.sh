# timeout=700
git pull -q origin main 2>&1 | tail -1; git log --oneline | head -1; flutter test 2>&1 | grep -E "^::error|tests passed|failed|Expected|Actual" | head -30
