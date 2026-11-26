// Benchmark and self-check. Runs the real kernels the way an audio thread would, so the numbers it gives are the
// numbers the engine will get on that phone. It allocates (vectors), so it must never run on an audio callback.
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <ctime>
#include <vector>

#include "da_core.h"

#if defined(__unix__) || defined(__APPLE__)
#include <time.h>
#endif

namespace da {
namespace {

constexpr double kFs = 48000.0;

int64_t nowNs(clockid_t id) {
  timespec ts;
  clock_gettime(id, &ts);
  return static_cast<int64_t>(ts.tv_sec) * 1000000000LL + ts.tv_nsec;
}

void sleepUntil(int64_t absNs) {
  timespec ts;
  ts.tv_sec = static_cast<time_t>(absNs / 1000000000LL);
  ts.tv_nsec = static_cast<long>(absNs % 1000000000LL);
#if defined(__linux__)
  while (clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &ts, nullptr) != 0) {
  }
#else
  (void)ts;
#endif
}

// Deterministic noise in [-0.5, 0.5): the same input on every phone.
struct Rng {
  uint32_t s = 0x9E3779B9u;
  float next() {
    s ^= s << 13;
    s ^= s >> 17;
    s ^= s << 5;
    return static_cast<float>(s >> 8) * (1.0f / 16777216.0f) - 0.5f;
  }
};

double percentile(std::vector<double>& v, double p) {
  if (v.empty()) return 0;
  std::sort(v.begin(), v.end());
  size_t idx = static_cast<size_t>(p * static_cast<double>(v.size() - 1) + 0.5);
  return v[std::min(idx, v.size() - 1)];
}

// One benchmark "workload": prepared once, then `process()` handles one block.
struct Work {
  virtual ~Work() {}
  virtual void process() = 0;
  virtual double macsPerBlock() const = 0;
  virtual double selfCheck() = 0;  // largest difference from the double-precision reference
};

struct SosWork : Work {
  int bands, block;
  bool dbl;                      // true: the real EQ (double state); false: the float version kept for comparison
  std::vector<double> sosD;      // ideal coefficients (double)
  std::vector<float> sosF, stateF, in, out;
  std::vector<double> stateD;
  SosWork(int b, int blk, bool d) : bands(b), block(blk), dbl(d) {
    static const double centers[] = {31.25, 62.5, 125, 250, 500, 1000, 2000, 4000, 8000, 16000};
    sosD.resize(static_cast<size_t>(5 * bands));
    sosF.resize(static_cast<size_t>(5 * bands));
    for (int i = 0; i < bands; ++i) {
      const double f = centers[i % 10] * (i >= 10 ? 1.1 : 1.0);
      peakingCoeffsD(kFs, f, (i % 2 == 0) ? 6.0 : -6.0, 1.4, &sosD[static_cast<size_t>(5 * i)]);
      for (int k = 0; k < 5; ++k) sosF[static_cast<size_t>(5 * i + k)] = static_cast<float>(sosD[static_cast<size_t>(5 * i + k)]);
    }
    stateF.assign(static_cast<size_t>(2 * bands) * 2, 0.f);  // two channels
    stateD.assign(static_cast<size_t>(2 * bands) * 2, 0.0);
    in.resize(static_cast<size_t>(blk) * 2);
    out.resize(static_cast<size_t>(blk) * 2);
    Rng r;
    for (auto& v : in) v = 0.4f * r.next();
  }
  void run(float* stF, double* stD, const float* x, float* y, int n) {
    if (dbl)
      sosProcessD(sosD.data(), bands, stD, x, y, n);
    else
      sosProcess(sosF.data(), bands, stF, x, y, n);
  }
  void process() override {
    run(stateF.data(), stateD.data(), in.data(), out.data(), block);
    run(stateF.data() + 2 * bands, stateD.data() + 2 * bands, in.data() + block, out.data() + block, block);
  }
  double macsPerBlock() const override { return 0; }
  double selfCheck() override {
    // 10 blocks of one channel against the ideal double reference (double coefficients, double state).
    std::vector<float> stF(static_cast<size_t>(2 * bands), 0.f);
    std::vector<double> stD(static_cast<size_t>(2 * bands), 0.0), stRef(static_cast<size_t>(2 * bands), 0.0);
    double maxErr = 0;
    Rng r;
    std::vector<float> x(static_cast<size_t>(block)), y(static_cast<size_t>(block));
    std::vector<double> xd(static_cast<size_t>(block)), yd(static_cast<size_t>(block));
    for (int b = 0; b < 10; ++b) {
      for (int i = 0; i < block; ++i) {
        x[static_cast<size_t>(i)] = 0.4f * r.next();
        xd[static_cast<size_t>(i)] = x[static_cast<size_t>(i)];
      }
      run(stF.data(), stD.data(), x.data(), y.data(), block);
      sosProcessRef(sosD.data(), bands, stRef.data(), xd.data(), yd.data(), block);
      for (int i = 0; i < block; ++i)
        maxErr = std::max(maxErr, std::fabs(static_cast<double>(y[static_cast<size_t>(i)]) - yd[static_cast<size_t>(i)]));
    }
    return maxErr;
  }
};

struct Fir4Work : Work {
  int taps, block;
  std::vector<float> h[4], hist[2], y[4];  // hist: [taps-1 history | block] for the two input channels
  Fir4Work(int t, int blk) : taps(t), block(blk) {
    Rng r;
    for (int f = 0; f < 4; ++f) {
      h[f].resize(static_cast<size_t>(taps));
      for (int k = 0; k < taps; ++k)  // decaying noise: the rough shape of a head-related impulse response
        h[f][static_cast<size_t>(k)] = r.next() * std::exp(-4.0f * static_cast<float>(k) / static_cast<float>(taps));
      y[f].resize(static_cast<size_t>(blk));
    }
    for (int c = 0; c < 2; ++c) {
      hist[c].assign(static_cast<size_t>(taps - 1 + blk), 0.f);
      for (int i = 0; i < blk; ++i) hist[c][static_cast<size_t>(taps - 1 + i)] = 0.4f * r.next();
    }
  }
  void process() override {
    // input channel 0 -> filters 0,1 ; input channel 1 -> filters 2,3
    for (int f = 0; f < 4; ++f) firSimd(hist[f / 2].data() + (taps - 1), h[f].data(), taps, y[f].data(), block);
  }
  double macsPerBlock() const override { return 4.0 * taps * block; }
  double selfCheck() override {
    std::vector<float> ref(static_cast<size_t>(block));
    double maxErr = 0;
    for (int f = 0; f < 4; ++f) {
      firRef(hist[f / 2].data() + (taps - 1), h[f].data(), taps, ref.data(), block);
      for (int i = 0; i < block; ++i)
        maxErr = std::max(maxErr, std::fabs(static_cast<double>(ref[static_cast<size_t>(i)]) - y[f][static_cast<size_t>(i)]));
    }
    return maxErr;
  }
};

}  // namespace

BenchResult runBench(int kernel, int taps, int block, int rtMs) {
  BenchResult r;
  r.kernel = kernel;
  r.taps = taps;
  r.block = block;
  if (block < 16 || block > 8192) {
    r.error = "block out of range";
    return r;
  }
  if (rtMs < 20 || rtMs > 60000) {
    r.error = "duration out of range";
    return r;
  }
  if (!cpuSimdOk()) {
    r.error = "this cpu has no NEON";
    return r;
  }
  Work* w = nullptr;
  if (kernel == kBenchSos || kernel == kBenchSosD) {
    if (taps < 1 || taps > kMaxSections) {
      r.error = "bands out of range";
      return r;
    }
    w = new SosWork(taps, block, kernel == kBenchSosD);
  } else if (kernel == kBenchFir4) {
    if (taps < 1 || taps > 8192) {
      r.error = "taps out of range";
      return r;
    }
    w = new Fir4Work(taps, block);
  } else {
    r.error = "unknown kernel";
    return r;
  }

  enableFlushToZero();
  const double blockNs = static_cast<double>(block) / kFs * 1e9;
  r.blockMs = blockNs / 1e6;

  // Warm up (lets the cpu governor raise the clock) then measure flat out for about 0.5 s.
  const int64_t t0 = nowNs(CLOCK_MONOTONIC);
  while (nowNs(CLOCK_MONOTONIC) - t0 < 300000000LL) w->process();
  int64_t start = nowNs(CLOCK_MONOTONIC);
  int64_t blocks = 0;
  while (nowNs(CLOCK_MONOTONIC) - start < 500000000LL) {
    for (int i = 0; i < 8; ++i) w->process();
    blocks += 8;
  }
  const int64_t flatNs = nowNs(CLOCK_MONOTONIC) - start;
  r.flatNsPerBlock = static_cast<double>(flatNs) / static_cast<double>(blocks);
  r.mmacs = w->macsPerBlock() > 0 ? w->macsPerBlock() * static_cast<double>(blocks) / (static_cast<double>(flatNs) / 1e9) / 1e6 : 0;

  // Paced like a real audio thread: one block every blockNs. The cpu may clock down between blocks, which is
  // exactly the effect we want to see.
  const int total = static_cast<int>(static_cast<double>(rtMs) * 1e6 / blockNs);
  std::vector<double> wall;
  wall.reserve(static_cast<size_t>(total));
  double cpuSum = 0;
  int misses = 0;
  int64_t deadline = nowNs(CLOCK_MONOTONIC) + static_cast<int64_t>(blockNs);
  for (int b = 0; b < total; ++b) {
    sleepUntil(deadline);
    const int64_t w0 = nowNs(CLOCK_MONOTONIC);
    const int64_t c0 = nowNs(CLOCK_THREAD_CPUTIME_ID);
    w->process();
    const int64_t c1 = nowNs(CLOCK_THREAD_CPUTIME_ID);
    const int64_t w1 = nowNs(CLOCK_MONOTONIC);
    wall.push_back(static_cast<double>(w1 - w0));
    cpuSum += static_cast<double>(c1 - c0);
    if (static_cast<double>(w1 - w0) > blockNs) ++misses;
    deadline += static_cast<int64_t>(blockNs);
    // If we fell far behind, do not try to catch up with a burst: re-anchor.
    if (nowNs(CLOCK_MONOTONIC) > deadline + static_cast<int64_t>(4 * blockNs)) deadline = nowNs(CLOCK_MONOTONIC) + static_cast<int64_t>(blockNs);
  }
  r.rtBlocks = total;
  r.rtMisses = misses;
  r.rtCpuNsAvg = total > 0 ? cpuSum / total : 0;
  r.rtWallNsMax = wall.empty() ? 0 : *std::max_element(wall.begin(), wall.end());
  r.rtWallNsP50 = percentile(wall, 0.50);
  r.rtWallNsP99 = percentile(wall, 0.99);
  r.loadPct = r.rtCpuNsAvg / blockNs * 100.0;
  r.loadP99Pct = r.rtWallNsP99 / blockNs * 100.0;
  r.maxErr = w->selfCheck();
  delete w;
  r.ok = true;
  return r;
}

}  // namespace da
