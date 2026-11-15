# timeout=1200
export JAVA_HOME=$JAVA_HOME_17_X64
git fetch -q origin main && git reset -q --hard origin/main && git log --oneline | head -1
bash ci/prepare_android.sh 2>&1 | tail -1
flutter build apk --release 2>&1 | tail -4
APK=build/app/outputs/flutter-apk/app-release.apk
echo "--- libs"; bash ci/check_native_libs.sh $APK; unzip -l $APK | grep -E "libdacore"
bash ci/check_signing.sh $APK
mkdir -p $DS_ART && cp $APK $DS_ART/directional-audio-0.5.0.apk
echo "--- which NDK / cmake did gradle use"
ls android/app/.cxx/*/*/ 2>/dev/null | head; grep -rh "CMAKE_ANDROID_NDK:\|CMAKE_COMMAND:\|CMAKE_BUILD_TYPE:\|CMAKE_CXX_FLAGS_RELEASE:" android/app/.cxx/*/*/arm*/CMakeCache.txt 2>/dev/null | sort -u | head
echo "--- disassembly check (armeabi-v7a)"
OBJ=$(ls /usr/local/lib/android/sdk/ndk/*/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-objdump | tail -1)
D=$(mktemp -d); unzip -q -o $APK 'lib/*/libdacore.so' -d $D
SO=$D/lib/armeabi-v7a/libdacore.so
$OBJ -d --no-show-raw-insn -C $SO > $D/v7.txt 2>&1
python3 - $D/v7.txt <<'PY'
import re,sys,collections
cur=None; neon=collections.Counter(); total=collections.Counter()
rx=re.compile(r'^\s*[0-9a-f]+:\s+(\S+)')
neon_rx=re.compile(r'^(vld1|vst1|vmla|vmul|vadd|vdup|vmov\.f32|vld2|vst2|vmls|vfma)\.(f32|32|8|16|64)?\b|^v(ld|st)[1-4]\.')
for l in open(sys.argv[1]):
    m=re.match(r'^[0-9a-f]+ <(.*)>:',l)
    if m: cur=m.group(1); continue
    m=rx.match(l)
    if m and cur:
        total[cur]+=1
        op=m.group(1)
        # q-register or d-register Advanced SIMD usage
        if re.search(r'\b[qd]\d+',l) and re.match(r'^v(ld|st|mla|mul|add|sub|dup|mov|fma|ext|zip|uzp|trn|rev|shl|shr|cvt|ceq|cgt|cge|max|min|abs|neg|and|orr|eor|bic|bsl|pad|set|get|ldr|str)',op):
            neon[cur]+=1
print("functions with Advanced-SIMD (q/d register) instructions:")
for k,v in neon.most_common(12): print(f"  {v:5d}  {k[:110]}")
print("total functions:",len(total))
PY
echo "--- flags actually used for kernels.cpp (v7a)"
grep -h "kernels.cpp" android/app/.cxx/*/*/armeabi-v7a/compile_commands.json 2>/dev/null | head -3 | cut -c1-400
grep -h -B2 -A2 "kernels.cpp" android/app/.cxx/*/*/armeabi-v7a/compile_commands.json 2>/dev/null | grep "command" | head -1 | grep -o "\-mfpu=[a-z0-9-]*\|-O[0-3s]\|-mfloat-abi=[a-z]*\|-march=[a-z0-9-]*" | sort -u
