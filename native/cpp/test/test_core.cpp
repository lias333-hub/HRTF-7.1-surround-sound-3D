// Host tests for the core. Run on a normal computer (see ci/cpp_tests.sh), also under AddressSanitizer and
// UndefinedBehaviorSanitizer. No test framework: a failed check is printed and the exit code is non-zero.
#include <cmath>
#include <cstdio>
#include <cstring>
#include <vector>

#include "../include/da_core.h"
#include "golden.h"

static int g_failed = 0, g_checks = 0;

#define CHECK(cond)                                                          \
  do {                                                                       \
    ++g_checks;                                                              \
    if (!(cond)) {                                                           \
      ++g_failed;                                                            \
      std::printf("FAIL %s:%d  %s\n", __FILE__, __LINE__, #cond);            \
    }                                                                        \
  } while (0)

#define CHECK_NEAR(a, b, tol)                                                                     \
  do {                                                                                            \
    ++g_checks;                                                                                   \
    const double _a = (a), _b = (b);                                                              \
    if (!(std::fabs(_a - _b) <= (tol))) {                                                         \
      ++g_failed;                                                                                 \
      std::printf("FAIL %s:%d  %s ~ %s: %.9g vs %.9g (tol %g)\n", __FILE__, __LINE__, #a, #b, _a, _b, (double)(tol)); \
    }                                                                                             \
  } while (0)

struct Lcg {  // tiny deterministic generator (the tests must not depend on libc rand)
  uint32_t s = 12345u;
  float next() {
    s = s * 1664525u + 1013904223u;
    return static_cast<float>(s >> 8) * (1.0f / 16777216.0f) * 2.f - 1.f;
  }
};

static void testInfo() {
  CHECK(std::strcmp(da::version(), "0.1.0") == 0);
  CHECK(da::arch() != nullptr && da::arch()[0] != 0);
  CHECK(da::pointerBits() == 32 || da::pointerBits() == 64);
  CHECK(da::cpuSimdOk());
#ifdef NDEBUG
  CHECK(da::optimizedBuild());  // a release build must really be optimised (the app warns when it is not)
#else
  (void)da::optimizedBuild();
#endif
  da::enableFlushToZero();  // must not crash
}

static void testSosGolden() {
  std::vector<float> state(2 * kGoldSections, 0.f), y(kGoldN);
  da::sosProcess(kGoldSos, kGoldSections, state.data(), kGoldX, y.data(), kGoldN);
  double maxErr = 0;
  for (int i = 0; i < kGoldN; ++i) maxErr = std::fmax(maxErr, std::fabs(y[i] - kGoldSosY[i]));
  std::printf("  sos vs scipy: max error %.3e\n", maxErr);
  CHECK(maxErr < 1e-5);

  // The double reference must match scipy almost exactly.
  std::vector<double> sosD(kGoldSos, kGoldSos + 5 * kGoldSections), stD(2 * kGoldSections, 0.0), xd(kGoldX, kGoldX + kGoldN), yd(kGoldN);
  da::sosProcessRef(sosD.data(), kGoldSections, stD.data(), xd.data(), yd.data(), kGoldN);
  double refErr = 0;
  for (int i = 0; i < kGoldN; ++i) refErr = std::fmax(refErr, std::fabs(yd[i] - kGoldSosY[i]));
  CHECK(refErr < 1e-12);

  // The double-state kernel (float in/out) must match scipy to float rounding.
  std::vector<double> stD2(2 * kGoldSections, 0.0);
  std::vector<float> yD(kGoldN);
  da::sosProcessD(sosD.data(), kGoldSections, stD2.data(), kGoldX, yD.data(), kGoldN);
  double dErr = 0;
  for (int i = 0; i < kGoldN; ++i) dErr = std::fmax(dErr, std::fabs(yD[i] - kGoldSosY[i]));
  std::printf("  sosD vs scipy: max error %.3e\n", dErr);
  CHECK(dErr < 1e-6);
}

// Finding F-01: float32 biquads are not accurate enough at low frequencies; the double-state kernel is.
static void testLowFrequencyAccuracy() {
  const double fcs[] = {31.25, 62.5, 125, 250, 500, 1000, 2000, 4000, 8000, 16000};
  Lcg r;
  std::vector<float> x(48000), yF(48000), yD(48000);
  std::vector<double> xd(48000), yRef(48000);
  for (int i = 0; i < 48000; ++i) {
    x[i] = 0.4f * r.next();
    xd[i] = x[i];
  }
  double worstD = 0, floatAt31 = 0;
  for (double f : fcs) {
    double cd[5];
    float cf[5];
    da::peakingCoeffsD(48000, f, 6.0, 1.4, cd);
    da::peakingCoeffs(48000, f, 6.0, 1.4, cf);
    float stF[2] = {0, 0};
    double stD[2] = {0, 0}, stR[2] = {0, 0};
    da::sosProcess(cf, 1, stF, x.data(), yF.data(), 48000);
    da::sosProcessD(cd, 1, stD, x.data(), yD.data(), 48000);
    da::sosProcessRef(cd, 1, stR, xd.data(), yRef.data(), 48000);
    double eF = 0, eD = 0, rms = 0;
    for (int i = 0; i < 48000; ++i) {
      eF = std::fmax(eF, std::fabs(yF[i] - yRef[i]));
      eD = std::fmax(eD, std::fabs(yD[i] - yRef[i]));
      rms += yRef[i] * yRef[i];
    }
    rms = std::sqrt(rms / 48000);
    std::printf("  %8.2f Hz: float err %.2e (%.0f dB)   double-state err %.2e (%.0f dB)\n", f, eF, 20 * std::log10(eF / rms), eD,
                20 * std::log10(eD / rms));
    worstD = std::fmax(worstD, eD);
    if (f == 31.25) floatAt31 = eF;
  }
  CHECK(worstD < 5e-7);          // better than -120 dB at every band
  CHECK(floatAt31 > 1e-5);       // documents why the float kernel is not used for the EQ
}

static void testSosStreaming() {
  // Processing in odd-sized chunks must give exactly the same samples as processing everything at once.
  std::vector<float> s1(2 * kGoldSections, 0.f), s2(2 * kGoldSections, 0.f), whole(kGoldN), chunked(kGoldN);
  da::sosProcess(kGoldSos, kGoldSections, s1.data(), kGoldX, whole.data(), kGoldN);
  const int sizes[] = {1, 7, 64, 100, 3, 305};  // sums to 480
  int pos = 0;
  for (int sz : sizes) {
    da::sosProcess(kGoldSos, kGoldSections, s2.data(), kGoldX + pos, chunked.data() + pos, sz);
    pos += sz;
  }
  CHECK(pos == kGoldN);
  CHECK(std::memcmp(whole.data(), chunked.data(), sizeof(float) * kGoldN) == 0);
  // in-place is allowed
  std::vector<float> s3(2 * kGoldSections, 0.f), inplace(kGoldX, kGoldX + kGoldN);
  da::sosProcess(kGoldSos, kGoldSections, s3.data(), inplace.data(), inplace.data(), kGoldN);
  CHECK(std::memcmp(whole.data(), inplace.data(), sizeof(float) * kGoldN) == 0);
}

static void testPeaking() {
  for (int c = 0; c < kGoldPeakCases; ++c) {
    float co[5];
    da::peakingCoeffs(kGoldPeakIn[4 * c + 0], kGoldPeakIn[4 * c + 1], kGoldPeakIn[4 * c + 2], kGoldPeakIn[4 * c + 3], co);
    for (int i = 0; i < 5; ++i) CHECK_NEAR(co[i], kGoldPeakOut[5 * c + i], 1e-6);
  }
  // 0 dB: the filter must be transparent.
  float co[5];
  da::peakingCoeffs(48000, 1000, 0.0, 1.4, co);
  std::vector<float> st(2, 0.f), y(kGoldN);
  da::sosProcess(co, 1, st.data(), kGoldX, y.data(), kGoldN);
  double maxErr = 0;
  for (int i = 0; i < kGoldN; ++i) maxErr = std::fmax(maxErr, std::fabs(y[i] - kGoldX[i]));
  CHECK(maxErr < 1e-5);
  // +6 dB peak at 1 kHz: a 1 kHz tone must come out about 6 dB louder (measured after the filter has settled).
  da::peakingCoeffs(48000, 1000, 6.0, 1.4, co);
  std::vector<float> in(48000), out(48000), st2(2, 0.f);
  for (int i = 0; i < 48000; ++i) in[i] = 0.1f * std::sin(2.0 * 3.14159265358979323846 * 1000.0 * i / 48000.0);
  da::sosProcess(co, 1, st2.data(), in.data(), out.data(), 48000);
  double pi = 0, po = 0;
  for (int i = 24000; i < 48000; ++i) {
    pi += static_cast<double>(in[i]) * in[i];
    po += static_cast<double>(out[i]) * out[i];
  }
  const double gainDb = 10.0 * std::log10(po / pi);
  std::printf("  peaking +6 dB at 1 kHz: measured %.3f dB\n", gainDb);
  CHECK_NEAR(gainDb, 6.0, 0.05);
}

static void testFirGolden() {
  const int taps = kGoldTaps;
  std::vector<float> buf(taps - 1 + kGoldN, 0.f), ySimd(kGoldN), yRef(kGoldN);
  std::memcpy(buf.data() + taps - 1, kGoldX, sizeof(float) * kGoldN);
  da::firSimd(buf.data() + taps - 1, kGoldH, taps, ySimd.data(), kGoldN);
  da::firRef(buf.data() + taps - 1, kGoldH, taps, yRef.data(), kGoldN);
  double eS = 0, eR = 0;
  for (int i = 0; i < kGoldN; ++i) {
    eS = std::fmax(eS, std::fabs(ySimd[i] - kGoldFirY[i]));
    eR = std::fmax(eR, std::fabs(yRef[i] - kGoldFirY[i]));
  }
  std::printf("  fir vs numpy: simd %.3e, ref %.3e\n", eS, eR);
  CHECK(eS < 2e-5);
  CHECK(eR < 1e-6);
}

static void testFirSimdVsRef() {
  const int tapsList[] = {1, 2, 3, 4, 5, 7, 16, 17, 64, 129, 256};
  const int nList[] = {1, 3, 4, 5, 15, 16, 17, 31, 33, 480};
  Lcg r;
  double worst = 0;
  for (int taps : tapsList) {
    for (int n : nList) {
      std::vector<float> buf(taps - 1 + n), h(taps), a(n), b(n);
      for (auto& v : buf) v = 0.5f * r.next();
      for (auto& v : h) v = r.next() / std::sqrt(static_cast<float>(taps));
      da::firSimd(buf.data() + taps - 1, h.data(), taps, a.data(), n);
      da::firRef(buf.data() + taps - 1, h.data(), taps, b.data(), n);
      for (int i = 0; i < n; ++i) worst = std::fmax(worst, std::fabs(a[i] - b[i]));
    }
  }
  std::printf("  fir simd vs ref over many sizes: worst %.3e\n", worst);
  CHECK(worst < 2e-6);
}

static void testFirStreaming() {
  // Block by block with history carried over must equal one long convolution.
  const int taps = 100, blk = 480, blocks = 5;
  Lcg r;
  std::vector<float> h(taps), x(blk * blocks);
  for (auto& v : h) v = r.next() / 10.f;
  for (auto& v : x) v = 0.5f * r.next();
  std::vector<float> longBuf(taps - 1 + x.size(), 0.f), whole(x.size());
  std::memcpy(longBuf.data() + taps - 1, x.data(), sizeof(float) * x.size());
  da::firRef(longBuf.data() + taps - 1, h.data(), taps, whole.data(), static_cast<int>(x.size()));

  std::vector<float> work(taps - 1 + blk, 0.f), y(blk);
  double worst = 0;
  for (int b = 0; b < blocks; ++b) {
    // shift: keep the last taps-1 samples as history
    if (b > 0) std::memmove(work.data(), work.data() + blk, sizeof(float) * (taps - 1));
    std::memcpy(work.data() + taps - 1, x.data() + b * blk, sizeof(float) * blk);
    da::firSimd(work.data() + taps - 1, h.data(), taps, y.data(), blk);
    for (int i = 0; i < blk; ++i) worst = std::fmax(worst, std::fabs(y[i] - whole[b * blk + i]));
  }
  std::printf("  fir streaming vs whole: worst %.3e\n", worst);
  CHECK(worst < 2e-6);
}

static void testBench() {
  da::BenchResult f = da::runBench(da::kBenchFir4, 64, 480, 100);
  CHECK(f.ok);
  CHECK(f.maxErr < 1e-5);
  CHECK(f.rtBlocks >= 5);
  CHECK(f.flatNsPerBlock > 0 && f.mmacs > 0);
  CHECK(f.loadPct >= 0);
  da::BenchResult s = da::runBench(da::kBenchSosD, 10, 480, 100);
  CHECK(s.ok);
  CHECK(s.maxErr < 5e-7);
  da::BenchResult sf = da::runBench(da::kBenchSos, 10, 480, 100);
  CHECK(sf.ok);
  CHECK(sf.maxErr > s.maxErr);  // the float kernel is measurably worse than the double-state one
  std::printf("  bench host: fir4/64 %.0f ns/block (%.0f MMAC/s, self-check %.1e); sosD 10x2 %.0f ns/block (%.1e); sos float %.0f ns/block (%.1e)\n",
              f.flatNsPerBlock, f.mmacs, f.maxErr, s.flatNsPerBlock, s.maxErr, sf.flatNsPerBlock, sf.maxErr);
  CHECK(!da::runBench(9, 64, 480, 100).ok);
  CHECK(!da::runBench(da::kBenchFir4, 0, 480, 100).ok);
  CHECK(!da::runBench(da::kBenchFir4, 64, 8, 100).ok);
  CHECK(!da::runBench(da::kBenchSos, 33, 480, 100).ok);
  CHECK(!da::runBench(da::kBenchSos, 10, 480, 5).ok);
}

int main() {
  std::printf("dacore %s on %s (%d-bit)\n", da::version(), da::arch(), da::pointerBits());
  testInfo();
  testSosGolden();
  testSosStreaming();
  testLowFrequencyAccuracy();
  testPeaking();
  testFirGolden();
  testFirSimdVsRef();
  testFirStreaming();
  testBench();
  std::printf("%d checks, %d failed\n", g_checks, g_failed);
  return g_failed == 0 ? 0 : 1;
}
