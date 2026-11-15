# timeout=600
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"; pwd; flutter analyze 2>&1 | tail -40; flutter test 2>&1 | tail -60
