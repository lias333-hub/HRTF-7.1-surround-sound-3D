# timeout=60
f=$(find . -name "TEST-*OutputRoutingTest.xml" | head -1); echo $f; grep -o "tests=\"[0-9]*\" skipped=\"[0-9]*\" failures=\"[0-9]*\" errors=\"[0-9]*\"" "$f"
