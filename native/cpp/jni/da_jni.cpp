// Thin JNI glue. All logic lives in the core; this file only converts types.
#include <jni.h>

#include <cstdio>
#include <string>

#include "da_core.h"

namespace {

jstring str(JNIEnv* env, const std::string& s) { return env->NewStringUTF(s.c_str()); }

jstring nativeInfo(JNIEnv* env, jclass) {
  char buf[256];
  std::snprintf(buf, sizeof buf, "ok=1;version=%s;arch=%s;bits=%d;neonCompiled=%d;simdOk=%d;opt=%d", da::version(), da::arch(),
                da::pointerBits(), da::simdCompiledWithNeon() ? 1 : 0, da::cpuSimdOk() ? 1 : 0,
                da::optimizedBuild() ? 1 : 0);
  return str(env, buf);
}

jstring nativeBench(JNIEnv* env, jclass, jint kernel, jint taps, jint block, jint rtMs) {
  try {
    const da::BenchResult r = da::runBench(kernel, taps, block, rtMs);
    char buf[640];
    if (!r.ok) {
      std::snprintf(buf, sizeof buf, "ok=0;error=%s", r.error);
    } else {
      std::snprintf(buf, sizeof buf,
                    "ok=1;kernel=%d;taps=%d;block=%d;blockMs=%.3f;flatNs=%.0f;mmacs=%.1f;rtBlocks=%d;rtMisses=%d;"
                    "cpuNs=%.0f;p50Ns=%.0f;p99Ns=%.0f;maxNs=%.0f;loadPct=%.2f;loadP99Pct=%.2f;maxErr=%.3e",
                    r.kernel, r.taps, r.block, r.blockMs, r.flatNsPerBlock, r.mmacs, r.rtBlocks, r.rtMisses, r.rtCpuNsAvg,
                    r.rtWallNsP50, r.rtWallNsP99, r.rtWallNsMax, r.loadPct, r.loadP99Pct, r.maxErr);
    }
    return str(env, buf);
  } catch (...) {
    return str(env, "ok=0;error=exception in native benchmark");
  }
}

const JNINativeMethod kMethods[] = {
    {"nativeInfo", "()Ljava/lang/String;", reinterpret_cast<void*>(nativeInfo)},
    {"nativeBench", "(IIII)Ljava/lang/String;", reinterpret_cast<void*>(nativeBench)},
};

}  // namespace

extern "C" JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void*) {
  JNIEnv* env = nullptr;
  if (vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) != JNI_OK) return JNI_ERR;
  jclass c = env->FindClass("com/directionalaudio/directional_audio/NativeCore");
  if (c == nullptr) return JNI_ERR;
  if (env->RegisterNatives(c, kMethods, sizeof kMethods / sizeof kMethods[0]) != JNI_OK) return JNI_ERR;
  return JNI_VERSION_1_6;
}
