# timeout=1200
export JAVA_HOME=$JAVA_HOME_17_X64
git fetch -q origin main && git reset -q --hard origin/main && git log --oneline | head -1
rm -rf android/app/.cxx
bash ci/prepare_android.sh 2>&1 | tail -1
tail -22 android/app/build.gradle
flutter build apk --release 2>&1 | tail -3
APK=build/app/outputs/flutter-apk/app-release.apk
echo "--- libs"; unzip -l $APK | grep -E "libdacore"; bash ci/check_native_libs.sh $APK
mkdir -p $DS_ART && cp $APK $DS_ART/directional-audio-0.5.0.apk
CC=$(ls android/app/.cxx/*/*/armeabi-v7a/compile_commands.json | head -1)
echo "--- per-file flags (v7a)"
python3 - $CC <<'PY'
import json,sys,re
for e in json.load(open(sys.argv[1])):
    f=e['file'].split('/cpp/')[-1]
    c=e.get('command') or ' '.join(e['arguments'])
    print(f, sorted(set(re.findall(r'-O[0-3s]|-mfpu=\S+|-march=\S+|-mfloat-abi=\S+|-ffast-math|-g\b|-DNDEBUG',c))))
PY
OBJ=$(ls /usr/local/lib/android/sdk/ndk/*/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-objdump | head -1)
echo "objdump: $OBJ"
D=$(mktemp -d); unzip -q -o $APK 'lib/*/libdacore.so' -d $D
for abi in armeabi-v7a arm64-v8a; do $OBJ -d --no-show-raw-insn -C $D/lib/$abi/libdacore.so > $D/$abi.txt 2>&1; done
python3 - $D/armeabi-v7a.txt <<'PY'
import re,sys,collections
cur=None; neon=collections.Counter(); samples={}
for l in open(sys.argv[1]):
    m=re.match(r'^[0-9a-f]+ <(.*)>:',l)
    if m: cur=m.group(1); continue
    m=re.match(r'^\s*[0-9a-f]+:\s+(\S+)\s*(.*)',l)
    if not (m and cur): continue
    op,args=m.group(1),m.group(2)
    if not op.startswith('v'): continue
    isneon = bool(re.search(r'\bq\d+',args)) or op.split('.')[0] in ('vld1','vst1','vld2','vst2','vld3','vst3','vld4','vst4','vdup','vext','vtbl','vzip','vuzp','vtrn','vrev64') \
        or (re.search(r'\.(f32|i32|s32|u32|32|16|8)$',op) and re.search(r'\bd\d+',args) and op.split('.')[0] not in ('vldr','vstr','vmov','vcvt','vcmp','vcmpe','vsqrt','vabs','vneg') and not re.search(r'\bs\d+',args))
    if isneon:
        neon[cur]+=1; samples.setdefault(cur,l.strip())
print("v7a functions containing NEON (not VFP) instructions:")
for k,v in neon.most_common(): print(f"  {v:5d}  {k[:100]}   e.g. {samples[k][:60]}")
if not neon: print("  none")
PY
python3 - $D/arm64-v8a.txt <<'PY'
import re,sys
n=0
for l in open(sys.argv[1]):
    if re.search(r'\bfmla\s+v\d+\.4s',l): n+=1
print("arm64: fmla v.4s (NEON fused multiply-add) instructions:",n)
PY
