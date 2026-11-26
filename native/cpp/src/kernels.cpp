// The signal-processing kernels. On 32-bit ARM this file alone is compiled with -mfpu=neon (see CMakeLists.txt) and
// is only called after cpuSimdOk() said yes, so a phone without NEON can never hit an illegal instruction.
#include <cstring>

#include "da_core.h"

namespace da {

// 4 floats. The compiler turns operations on this type into NEON (ARM) or SSE (x86) instructions.
typedef float v4f __attribute__((vector_size(16)));

static inline v4f ld(const float* p) {
  v4f r;
  std::memcpy(&r, p, sizeof r);  // unaligned-safe load
  return r;
}
static inline void st(float* p, v4f v) { std::memcpy(p, &v, sizeof v); }
static inline v4f splat(float s) { return (v4f){s, s, s, s}; }

void sosProcess(const float* sos, int sections, float* state, const float* in, float* out, int n) {
  for (int i = 0; i < n; ++i) {
    float v = in[i];
    for (int s = 0; s < sections; ++s) {
      const float* c = sos + 5 * s;
      float* z = state + 2 * s;
      const float y = c[0] * v + z[0];
      z[0] = c[1] * v - c[3] * y + z[1];
      z[1] = c[2] * v - c[4] * y;
      v = y;
    }
    out[i] = v;
  }
}

void sosProcessD(const double* sos, int sections, double* state, const float* in, float* out, int n) {
  for (int i = 0; i < n; ++i) {
    double v = in[i];
    for (int s = 0; s < sections; ++s) {
      const double* c = sos + 5 * s;
      double* z = state + 2 * s;
      const double y = c[0] * v + z[0];
      z[0] = c[1] * v - c[3] * y + z[1];
      z[1] = c[2] * v - c[4] * y;
      v = y;
    }
    out[i] = static_cast<float>(v);
  }
}

void sosProcessRef(const double* sos, int sections, double* state, const double* in, double* out, int n) {
  for (int i = 0; i < n; ++i) {
    double v = in[i];
    for (int s = 0; s < sections; ++s) {
      const double* c = sos + 5 * s;
      double* z = state + 2 * s;
      const double y = c[0] * v + z[0];
      z[0] = c[1] * v - c[3] * y + z[1];
      z[1] = c[2] * v - c[4] * y;
      v = y;
    }
    out[i] = v;
  }
}

void firRef(const float* x, const float* h, int taps, float* y, int n) {
  for (int i = 0; i < n; ++i) {
    double acc = 0.0;
    for (int k = 0; k < taps; ++k) acc += static_cast<double>(h[k]) * static_cast<double>(x[i - k]);
    y[i] = static_cast<float>(acc);
  }
}

void firSimd(const float* x, const float* h, int taps, float* y, int n) {
  int i = 0;
  const v4f zero = {0.f, 0.f, 0.f, 0.f};
  // 16 outputs at a time: four independent accumulators keep the multiply-add units busy.
  for (; i + 16 <= n; i += 16) {
    v4f a0 = zero, a1 = zero, a2 = zero, a3 = zero;
    const float* xp = x + i;
    for (int k = 0; k < taps; ++k) {
      const v4f hk = splat(h[k]);
      const float* p = xp - k;
      a0 += hk * ld(p);
      a1 += hk * ld(p + 4);
      a2 += hk * ld(p + 8);
      a3 += hk * ld(p + 12);
    }
    st(y + i, a0);
    st(y + i + 4, a1);
    st(y + i + 8, a2);
    st(y + i + 12, a3);
  }
  for (; i + 4 <= n; i += 4) {
    v4f a = zero;
    for (int k = 0; k < taps; ++k) a += splat(h[k]) * ld(x + i - k);
    st(y + i, a);
  }
  for (; i < n; ++i) {
    float acc = 0.f;
    for (int k = 0; k < taps; ++k) acc += h[k] * x[i - k];
    y[i] = acc;
  }
}

}  // namespace da
