# timeout=60
grep -ho "tests=\"[0-9]*\" skipped=\"[0-9]*\" failures=\"[0-9]*\" errors=\"[0-9]*\"" android/app/build/test-results/testDebugUnitTest/*.xml
