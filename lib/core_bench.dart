import 'package:flutter/services.dart';

/// Parses the "key=value;key=value" text the native core answers with. Unknown or malformed parts are skipped.
Map<String, String> parseKv(String raw) {
  final out = <String, String>{};
  for (final part in raw.split(';')) {
    final i = part.indexOf('=');
    if (i <= 0) continue;
    out[part.substring(0, i).trim()] = part.substring(i + 1).trim();
  }
  return out;
}

/// What the native core says about itself and the phone's CPU.
class CoreInfo {
  const CoreInfo({
    required this.loaded,
    this.error = '',
    this.version = '',
    this.arch = '',
    this.bits = 0,
    this.neonCompiled = false,
    this.simdOk = false,
    this.optimized = false,
    this.abis = const [],
  });

  /// False when the library did not load (an ABI we did not build, a failed load) or there is no native side.
  final bool loaded;
  final String error;
  final String version;
  final String arch;
  final int bits;
  final bool neonCompiled;
  final bool simdOk;

  /// Compiled with optimisation. A benchmark of an unoptimised build means nothing.
  final bool optimized;

  /// The phone's supported ABIs, best first (Build.SUPPORTED_ABIS).
  final List<String> abis;

  factory CoreInfo.unavailable(String error) => CoreInfo(loaded: false, error: error);

  factory CoreInfo.fromMap(Map<dynamic, dynamic> m) {
    final kv = parseKv('${m['raw'] ?? ''}');
    final abis = <String>[for (final a in (m['abis'] as List? ?? const [])) '$a'];
    if (kv['ok'] != '1') {
      return CoreInfo(loaded: false, error: kv['error'] ?? 'no answer', abis: abis);
    }
    return CoreInfo(
      loaded: true,
      version: kv['version'] ?? '',
      arch: kv['arch'] ?? '',
      bits: int.tryParse(kv['bits'] ?? '') ?? 0,
      neonCompiled: kv['neonCompiled'] == '1',
      simdOk: kv['simdOk'] == '1',
      optimized: kv['opt'] == '1',
      abis: abis,
    );
  }

  /// One technical line (English, shown left-to-right like the event log).
  String get line =>
      'core $version | $arch ${bits}-bit | neon=${neonCompiled ? 1 : 0} simd=${simdOk ? 1 : 0} '
      'opt=${optimized ? 1 : 0} | phone abis=${abis.join(",")}';
}

/// Native kernel ids (they match da::BenchKernel in the C++ core).
const int kBenchSos = 1; // float biquads
const int kBenchFir4 = 2; // 4 FIR filters: 2 virtual speakers x 2 ears
const int kBenchSosD = 3; // double-state biquads: the real equalizer

/// One benchmark case. For the biquad kernels [taps] is the number of EQ bands.
class BenchCase {
  const BenchCase(this.kernel, this.taps, this.block);
  final int kernel;
  final int taps;
  final int block;

  String get name => switch (kernel) {
        kBenchSos => 'eq float ${taps}b',
        kBenchSosD => 'eq double ${taps}b',
        kBenchFir4 => 'fir4 ${taps}t',
        _ => 'kernel$kernel',
      };
}

/// The cases the "core speed test" runs, in order. 480 samples = 10 ms at 48 kHz.
const List<BenchCase> kBenchSuite = [
  BenchCase(kBenchSos, 10, 480),
  BenchCase(kBenchSosD, 10, 480),
  BenchCase(kBenchFir4, 128, 480),
  BenchCase(kBenchFir4, 256, 480),
  BenchCase(kBenchFir4, 512, 480),
];

/// How long the real-time (paced) phase of each case lasts.
const int kBenchRtMs = 2000;

/// 7.1 is 8 virtual speakers x 2 ears = 16 FIR filters, i.e. 4x the 4-filter case (2 speakers x 2 ears).
const int kFullSurroundFactor = 4;

class BenchResult {
  const BenchResult({
    required this.ok,
    this.error = '',
    this.kernel = 0,
    this.taps = 0,
    this.block = 0,
    this.blockMs = 0,
    this.flatNs = 0,
    this.mmacs = 0,
    this.rtBlocks = 0,
    this.rtMisses = 0,
    this.cpuNs = 0,
    this.p50Ns = 0,
    this.p99Ns = 0,
    this.maxNs = 0,
    this.loadPct = 0,
    this.loadP99Pct = 0,
    this.maxErr = 0,
  });

  final bool ok;
  final String error;
  final int kernel, taps, block;
  final double blockMs;
  final double flatNs; // flat out: ns per block
  final double mmacs; // million multiply-adds per second (FIR only)
  final int rtBlocks, rtMisses;
  final double cpuNs; // thread CPU time per block while paced
  final double p50Ns, p99Ns, maxNs; // wall time per block while paced
  final double loadPct; // cpuNs / block duration
  final double loadP99Pct; // p99 wall / block duration
  final double maxErr; // largest difference from the double-precision reference

  factory BenchResult.failed(String error) => BenchResult(ok: false, error: error);

  factory BenchResult.parse(String raw) {
    final kv = parseKv(raw);
    if (kv['ok'] != '1') return BenchResult.failed(kv['error'] ?? 'no answer');
    double d(String k) => double.tryParse(kv[k] ?? '') ?? 0;
    int i(String k) => int.tryParse(kv[k] ?? '') ?? 0;
    return BenchResult(
      ok: true,
      kernel: i('kernel'),
      taps: i('taps'),
      block: i('block'),
      blockMs: d('blockMs'),
      flatNs: d('flatNs'),
      mmacs: d('mmacs'),
      rtBlocks: i('rtBlocks'),
      rtMisses: i('rtMisses'),
      cpuNs: d('cpuNs'),
      p50Ns: d('p50Ns'),
      p99Ns: d('p99Ns'),
      maxNs: d('maxNs'),
      loadPct: d('loadPct'),
      loadP99Pct: d('loadP99Pct'),
      maxErr: d('maxErr'),
    );
  }

  /// Rough load of a full 7.1 simulation, from a 4-filter result (null for the other kernels).
  double? get surroundEstimatePct => kernel == kBenchFir4 ? loadPct * kFullSurroundFactor : null;

  /// One technical line (English): used on screen, in the event log and in the copied report.
  String line(BenchCase c) {
    if (!ok) return '${c.name}: FAILED $error';
    final b = StringBuffer('${c.name} blk=$block | flat ${(flatNs / 1000).toStringAsFixed(1)} us');
    if (mmacs > 0) b.write(' (${mmacs.toStringAsFixed(0)} MMAC/s)');
    b.write(' | paced cpu ${loadPct.toStringAsFixed(1)}% p99 ${loadP99Pct.toStringAsFixed(1)}%'
        ' max ${(maxNs / 1000).toStringAsFixed(0)} us miss ${rtMisses}/$rtBlocks');
    final est = surroundEstimatePct;
    if (est != null) b.write(' | 7.1~${est.toStringAsFixed(0)}%');
    b.write(' | err ${maxErr.toStringAsExponential(1)}');
    return b.toString();
  }
}

/// Bridge to the native core's information and benchmark.
class CoreApi {
  static const _ch = MethodChannel('directional/eq');

  static Future<CoreInfo> info() async {
    try {
      final m = await _ch.invokeMethod<Map<dynamic, dynamic>>('coreInfo');
      return CoreInfo.fromMap(m ?? const {});
    } on MissingPluginException {
      return CoreInfo.unavailable('no native side');
    } on PlatformException catch (e) {
      return CoreInfo.unavailable(e.message ?? e.code);
    }
  }

  /// Runs one case (takes about 1 s plus [rtMs]). Never throws: a failure is a [BenchResult] with ok == false.
  static Future<BenchResult> bench(BenchCase c, {int rtMs = kBenchRtMs}) async {
    try {
      final raw = await _ch.invokeMethod<String>('coreBench', {
        'kernel': c.kernel,
        'taps': c.taps,
        'block': c.block,
        'rtMs': rtMs,
      });
      return BenchResult.parse(raw ?? '');
    } on MissingPluginException {
      return BenchResult.failed('no native side');
    } on PlatformException catch (e) {
      return BenchResult.failed(e.message ?? e.code);
    }
  }
}
