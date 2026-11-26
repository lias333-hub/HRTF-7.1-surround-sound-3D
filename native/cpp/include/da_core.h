// Directional Audio core (C++). Pure C++17, no Android or JNI types: everything here is unit-tested on a normal
// computer (host tests) and then run on the phone. The JNI glue lives in jni/da_jni.cpp.
//
// Rules for code in this core (they come from the project's priorities: sound quality and speed):
//  - nothing on the audio path allocates memory, takes a lock, logs, or touches the file system;
//  - no -ffast-math (it changes results); float is used for the signal, double only for design maths and references;
//  - every kernel has a plain reference implementation, and tests compare them against golden vectors made with
//    Python/scipy (tools/gen_golden.py).
#pragma once

#include <cstddef>
#include <cstdint>

namespace da {

constexpr const char* kCoreVersion = "0.1.0";

// ---- build and CPU facts ----------------------------------------------------------------------------
const char* version();
const char* arch();      // "armeabi-v7a" | "arm64-v8a" | "x86_64" | "x86" | "unknown"
int pointerBits();       // 32 or 64
bool simdCompiledWithNeon();  // true when this build targets ARM and was built with NEON kernels
// True when this library was compiled with optimisation on. A benchmark of a non-optimised build (-O0) is
// meaningless, so the app shows a warning when this is false.
bool optimizedBuild();
// True when the SIMD kernels may run on THIS cpu. On 32-bit ARM it checks the NEON bit at run time; 64-bit ARM
// always has it; on x86 the generic vector code is always fine.
bool cpuSimdOk();
// Flush denormal numbers to zero on the calling thread. Without it IIR filters can become several times slower
// when a tail decays into denormals (on x86 and on ARM VFP). Call once at the start of an audio thread.
void enableFlushToZero();

// ---- filter design ----------------------------------------------------------------------------------
// RBJ "Audio EQ Cookbook" peaking filter. Writes {b0, b1, b2, a1, a2} (a0 normalised to 1).
void peakingCoeffs(double fs, double f0, double gainDb, double q, float out[5]);
// The same in double precision. Use this one for the EQ: see sosProcessD.
void peakingCoeffsD(double fs, double f0, double gainDb, double q, double out[5]);

// ---- kernels ----------------------------------------------------------------------------------------
// Cascade of biquads (transposed direct form II), one channel. `sos` holds 5 floats per section
// {b0, b1, b2, a1, a2}; `state` holds 2 floats per section and is updated, so consecutive blocks continue
// seamlessly. `in` and `out` may be the same buffer. At most kMaxSections sections.
constexpr int kMaxSections = 32;
void sosProcess(const float* sos, int sections, float* state, const float* in, float* out, int n);
// Float state and coefficients are NOT good enough for low-frequency bands. Measured (tests, finding F-01): one
// float32 biquad at 31.25 Hz is only -60 dB below the signal, 62.5 Hz -69 dB, 125 Hz -76 dB (CD quality is -96 dB),
// because the poles sit very close to z = 1. The EQ therefore uses this version: double coefficients and double
// state, float input and output. It costs little (a 10-band stereo EQ is about 5 million multiply-adds a second).
void sosProcessD(const double* sos, int sections, double* state, const float* in, float* out, int n);
// Reference for tests: everything in double.
void sosProcessRef(const double* sos, int sections, double* state, const double* in, double* out, int n);

// FIR: y[i] = sum_{k=0}^{taps-1} h[k] * x[i-k]. `x` points at the first sample of the block and the `taps-1`
// samples before it (the history) must be readable. Reference: double accumulation.
void firRef(const float* x, const float* h, int taps, float* y, int n);
// 4-wide vector version (NEON on ARM, SSE on x86 through the compiler's generic vectors). Same contract.
void firSimd(const float* x, const float* h, int taps, float* y, int n);

// ---- benchmark --------------------------------------------------------------------------------------
enum BenchKernel { kBenchSos = 1 /* float */, kBenchFir4 = 2, kBenchSosD = 3 /* double state: the real EQ */ };

struct BenchResult {
  bool ok = false;
  const char* error = "";
  int kernel = 0, taps = 0, block = 0;
  double blockMs = 0;      // length of one block at 48 kHz
  // Flat out (as fast as possible): the best case.
  double flatNsPerBlock = 0;
  double mmacs = 0;        // million multiply-adds per second (FIR only)
  // Paced like a real audio thread (one block every blockMs): what actually matters.
  int rtBlocks = 0;
  int rtMisses = 0;        // blocks whose processing alone took longer than the block itself
  double rtCpuNsAvg = 0;   // thread CPU time per block
  double rtWallNsP50 = 0, rtWallNsP99 = 0, rtWallNsMax = 0;
  double loadPct = 0;      // rtCpuNsAvg / block duration
  double loadP99Pct = 0;   // rtWallNsP99 / block duration
  double maxErr = 0;       // largest difference from the double-precision reference (self-check)
};

// Runs one benchmark case. kBenchSos / kBenchSosD: `taps` is the number of EQ bands (sections), two channels. kBenchFir4: four
// FIR filters of `taps` taps (2 virtual speakers x 2 ears), the shape of stereo-to-binaural. `rtMs` = how long the
// paced phase lasts. Must be called from a normal thread, never from an audio callback (it allocates).
BenchResult runBench(int kernel, int taps, int block, int rtMs);

}  // namespace da
