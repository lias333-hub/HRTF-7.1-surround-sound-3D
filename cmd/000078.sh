# timeout=1200
export JAVA_HOME=$JAVA_HOME_17_X64
rm -rf build android/app/build android/app/.cxx
bash ci/prepare_android.sh 2>&1 | tail -1
flutter build apk --release 2>&1 | tail -3
APK=build/app/outputs/flutter-apk/app-release.apk
echo "--- libs in APK"; unzip -l $APK | grep -E "libdacore"; bash ci/check_native_libs.sh $APK
bash ci/check_signing.sh $APK
mkdir -p $DS_ART && cp $APK $DS_ART/directional-audio-0.5.0.apk
echo "--- unstripped libs"; find android/app/build -name libdacore.so | head
OBJ=$(ls /usr/local/lib/android/sdk/ndk/23*/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-objdump | head -1)
V7=$(find android/app/build -path '*RelWithDebInfo*' -path '*armeabi-v7a*' -name libdacore.so | head -1)
A64=$(find android/app/build -path '*RelWithDebInfo*' -path '*arm64-v8a*' -name libdacore.so | head -1)
echo "v7a: $V7"; echo "a64: $A64"
D=$(mktemp -d)
$OBJ -d --no-show-raw-insn -C "$V7" > $D/v7.txt 2>&1; $OBJ -d --no-show-raw-insn -C "$A64" > $D/a64.txt 2>&1
wc -l $D/v7.txt $D/a64.txt
python3 - $D/v7.txt <<'PY'
import re,sys,collections
cur=None; neon=collections.Counter(); samples={}; fn=collections.Counter()
for l in open(sys.argv[1]):
    m=re.match(r'^[0-9a-f]+ <(.*)>:',l)
    if m: cur=m.group(1); continue
    m=re.match(r'^\s*[0-9a-f]+:\s+(\S+)\s*(.*)',l)
    if not (m and cur): continue
    fn[cur]+=1
    op,args=m.group(1),m.group(2)
    if not op.startswith('v'): continue
    base=op.split('.')[0]
    isneon = bool(re.search(r'\bq\d+',args)) or base in ('vld1','vst1','vld2','vst2','vld3','vst3','vld4','vst4','vdup','vext','vtbl','vzip','vuzp','vtrn','vrev64') \
        or (re.search(r'\.(f32|i32|s32|u32|32|16|8)$',op) and re.search(r'\bd\d+',args) and base not in ('vldr','vstr','vmov','vcvt','vcmp','vcmpe','vsqrt','vabs','vneg') and not re.search(r'\bs\d+',args))
    if isneon:
        neon[cur]+=1; samples.setdefault(cur,l.strip())
print("v7a: functions with NEON (not VFP) instructions:")
for k,v in neon.most_common(): print(f"  {v:5d}  {k[:100]}   e.g. {samples[k][:60]}")
if not neon: print("  none")
print("v7a: da:: functions total:",sum(1 for k in fn if k.startswith('da::')), " instructions in firSimd:",[ (k[:40],v) for k,v in fn.items() if 'firSimd' in k])
PY
python3 - $D/a64.txt <<'PY'
import re,sys,collections
c=collections.Counter(); cur=None
for l in open(sys.argv[1]):
    m=re.match(r'^[0-9a-f]+ <(.*)>:',l)
    if m: cur=m.group(1); continue
    if re.search(r'\bfmla\s+v\d+\.4s|\bfmul\s+v\d+\.4s|\bld1\s+\{v',l) and cur: c[cur]+=1
print("arm64: functions with NEON 4s fmla/fmul/ld1:",[(k[:50],v) for k,v in c.most_common(6)])
PY
