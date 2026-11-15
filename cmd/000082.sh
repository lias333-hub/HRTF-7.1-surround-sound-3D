# timeout=600
export PATH=$PWD/ci/devshell/bin:$PATH
emu tapt 'Run test' 2>&1 | tail -1
sleep 6; emu shot bench_running >/dev/null 2>&1
sleep 22
emu ui 2>&1 | grep -E "eq float|eq double|fir4|Done|FAILED" 
emu shot bench_done 2>&1 | tail -1
echo "--- crashes"; emu crash 2>&1 | head -20
echo "--- log"; emu log 400 2>&1 | grep -i -E "dacore|bench|UnsatisfiedLink|SIGILL|FATAL" | head
