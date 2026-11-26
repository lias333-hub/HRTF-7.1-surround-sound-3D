#include "da_core.h"

#include <cmath>

#if defined(__linux__) && (defined(__arm__)) && !defined(__aarch64__)
#include <sys/auxv.h>
#include <asm/hwcap.h>
#endif
#if defined(__SSE__) || defined(__x86_64__) || defined(__i386__)
#include <xmmintrin.h>
#include <pmmintrin.h>
#endif

namespace da {

const char* version() { return kCoreVersion; }

const char* arch() {
#if defined(__aarch64__)
  return "arm64-v8a";
#elif defined(__arm__)
  return "armeabi-v7a";
#elif defined(__x86_64__)
  return "x86_64";
#elif defined(__i386__)
  return "x86";
#else
  return "unknown";
#endif
}

int pointerBits() { return static_cast<int>(sizeof(void*) * 8); }

bool simdCompiledWithNeon() {
#if defined(__aarch64__) || defined(__ARM_NEON)
  return true;
#else
  return false;
#endif
}

bool optimizedBuild() {
#if defined(__OPTIMIZE__)
  return true;
#else
  return false;
#endif
}

bool cpuSimdOk() {
#if defined(__aarch64__)
  return true;  // Advanced SIMD is mandatory on ARMv8-A
#elif defined(__arm__)
#if defined(HWCAP_NEON)
  return (getauxval(AT_HWCAP) & HWCAP_NEON) != 0;
#else
  return false;
#endif
#else
  return true;
#endif
}

void enableFlushToZero() {
#if defined(__aarch64__)
  uint64_t fpcr;
  __asm__ volatile("mrs %0, fpcr" : "=r"(fpcr));
  fpcr |= (1ull << 24);  // FZ
  __asm__ volatile("msr fpcr, %0" : : "r"(fpcr));
#elif defined(__arm__)
  uint32_t fpscr;
  __asm__ volatile("vmrs %0, fpscr" : "=r"(fpscr));
  fpscr |= (1u << 24);  // FZ
  __asm__ volatile("vmsr fpscr, %0" : : "r"(fpscr));
#elif defined(__SSE__) || defined(__x86_64__) || defined(__i386__)
  _MM_SET_FLUSH_ZERO_MODE(_MM_FLUSH_ZERO_ON);
  _MM_SET_DENORMALS_ZERO_MODE(_MM_DENORMALS_ZERO_ON);
#endif
}

void peakingCoeffsD(double fs, double f0, double gainDb, double q, double out[5]) {
  const double pi = 3.14159265358979323846;
  const double A = std::pow(10.0, gainDb / 40.0);
  const double w0 = 2.0 * pi * f0 / fs;
  const double alpha = std::sin(w0) / (2.0 * q);
  const double cw = std::cos(w0);
  const double b0 = 1.0 + alpha * A, b1 = -2.0 * cw, b2 = 1.0 - alpha * A;
  const double a0 = 1.0 + alpha / A, a1 = -2.0 * cw, a2 = 1.0 - alpha / A;
  out[0] = b0 / a0;
  out[1] = b1 / a0;
  out[2] = b2 / a0;
  out[3] = a1 / a0;
  out[4] = a2 / a0;
}

void peakingCoeffs(double fs, double f0, double gainDb, double q, float out[5]) {
  double d[5];
  peakingCoeffsD(fs, f0, gainDb, q, d);
  for (int i = 0; i < 5; ++i) out[i] = static_cast<float>(d[i]);
}

}  // namespace da
