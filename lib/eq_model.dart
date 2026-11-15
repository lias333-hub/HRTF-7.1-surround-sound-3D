import 'dart:math' as math;

/// Centre frequencies (Hz) of the 10 user-facing EQ bands.
const List<double> kBandFreqs = [
  31.25, 62.5, 125, 250, 500, 1000, 2000, 4000, 8000, 16000,
];
const double kMaxGain = 12;
const double kMinGain = -12;
const String kBuiltInPrefix = 'builtin:';

/// A named EQ curve: 10 band gains (dB) plus a global preamp offset (dB).
class EqProfile {
  const EqProfile({required this.name, required this.gains, this.preamp = 0});

  factory EqProfile.flat([String name = 'builtin:flat']) =>
      EqProfile(name: name, gains: List<double>.filled(kBandFreqs.length, 0));

  final String name;
  final List<double> gains;
  final double preamp;

  bool get isBuiltIn => name.startsWith(kBuiltInPrefix);

  EqProfile copyWith({String? name, List<double>? gains, double? preamp}) =>
      EqProfile(
        name: name ?? this.name,
        gains: gains ?? this.gains,
        preamp: preamp ?? this.preamp,
      );

  EqProfile withGain(int i, double v) {
    final g = List<double>.of(gains);
    g[i] = v.clamp(kMinGain, kMaxGain).toDouble();
    return copyWith(gains: g);
  }

  EqProfile withPreamp(double v) =>
      copyWith(preamp: v.clamp(kMinGain, kMaxGain).toDouble());

  Map<String, dynamic> toJson() =>
      {'name': name, 'gains': gains, 'preamp': preamp};

  static EqProfile? fromJson(Object? j) {
    if (j is! Map) return null;
    final name = j['name'];
    final gains = j['gains'];
    final pre = j['preamp'];
    if (name is! String || gains is! List || gains.length != kBandFreqs.length) {
      return null;
    }
    final g = <double>[];
    for (final v in gains) {
      if (v is! num) return null;
      g.add(v.toDouble().clamp(kMinGain, kMaxGain).toDouble());
    }
    final p = pre is num ? pre.toDouble().clamp(kMinGain, kMaxGain).toDouble() : 0.0;
    return EqProfile(name: name, gains: g, preamp: p);
  }
}

final List<EqProfile> kBuiltInProfiles = [
  EqProfile.flat(),
  const EqProfile(
      name: 'builtin:bass', gains: <double>[6, 5, 4, 2, 0, 0, 0, 0, 0, 0]),
  const EqProfile(
      name: 'builtin:vocal', gains: <double>[-2, -1, 0, 1, 2, 3, 3, 2, 0, -1]),
  const EqProfile(
      name: 'builtin:treble', gains: <double>[0, 0, 0, 0, 0, 1, 2, 4, 5, 6]),
  const EqProfile(
      name: 'builtin:soft', gains: <double>[1, 1, 0, 0, 0, 0, -1, -3, -3, -1]),
];

/// Gain (dB) of the 10-band curve at [hz]: linear in log-frequency between
/// band centres, flat beyond the first and last band.
double curveAt(List<double> gains, double hz) {
  if (hz <= kBandFreqs.first) return gains.first;
  if (hz >= kBandFreqs.last) return gains.last;
  for (var i = 0; i < kBandFreqs.length - 1; i++) {
    final a = kBandFreqs[i];
    final b = kBandFreqs[i + 1];
    if (hz <= b) {
      final t = (math.log(hz) - math.log(a)) / (math.log(b) - math.log(a));
      return gains[i] + (gains[i + 1] - gains[i]) * t;
    }
  }
  return gains.last;
}

/// Maps the 10-band curve onto the hardware equalizer's real bands.
/// Each hardware band gets the average of the curve over its frequency range
/// (7 log-spaced samples) plus [preamp], in millibels, clamped to the range
/// the device reports. Frequencies are in Hz.
List<int> deviceLevels({
  required List<double> gains,
  required double preamp,
  required List<double> lows,
  required List<double> highs,
  required List<double> centers,
  required int minMb,
  required int maxMb,
}) {
  final out = <int>[];
  for (var i = 0; i < centers.length; i++) {
    final lo = math.max(lows[i], 20.0);
    final hi = math.min(highs[i], 20000.0);
    double g;
    if (hi > lo * 1.01) {
      const n = 7;
      var sum = 0.0;
      for (var k = 0; k < n; k++) {
        final f = lo * math.pow(hi / lo, k / (n - 1));
        sum += curveAt(gains, f);
      }
      g = sum / n;
    } else {
      g = curveAt(gains, centers[i]);
    }
    out.add(((g + preamp) * 100).round().clamp(minMb, maxMb).toInt());
  }
  return out;
}

class ParsedEq {
  const ParsedEq(this.gains, this.preamp);
  final List<double> gains;
  final double preamp;
}

/// Parses text like `GraphicEQ: 20 -3.5; 25 -3.1; ...` (the format used by
/// Wavelet and AutoEq's GraphicEQ.txt). An optional `Preamp: -6 dB` line is
/// honoured. The points are resampled onto the 10 bands (average over +-half
/// an octave around each centre, snapped to 0.5 dB). Returns null when fewer
/// than two valid points are found.
ParsedEq? parseGraphicEq(String text) {
  final preMatch = RegExp(r'Preamp:\s*(-?\d+(?:\.\d+)?)\s*dB',
          caseSensitive: false)
      .firstMatch(text);
  final preamp = preMatch == null
      ? 0.0
      : double.parse(preMatch.group(1)!).clamp(kMinGain, kMaxGain).toDouble();
  final idx = text.toLowerCase().indexOf('graphiceq:');
  final body = idx >= 0 ? text.substring(idx + 'graphiceq:'.length) : text;
  final pts = <(double, double)>[];
  final re = RegExp(r'^\s*(\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)\s*$');
  for (final part in body.split(RegExp(r'[;\n]'))) {
    final m = re.firstMatch(part);
    if (m != null) {
      pts.add((double.parse(m.group(1)!), double.parse(m.group(2)!)));
    }
  }
  if (pts.length < 2) return null;
  pts.sort((a, b) => a.$1.compareTo(b.$1));

  double at(double hz) {
    if (hz <= pts.first.$1) return pts.first.$2;
    if (hz >= pts.last.$1) return pts.last.$2;
    for (var i = 0; i < pts.length - 1; i++) {
      final a = pts[i];
      final b = pts[i + 1];
      if (hz <= b.$1) {
        if (b.$1 == a.$1) return b.$2;
        final t = (math.log(hz) - math.log(a.$1)) /
            (math.log(b.$1) - math.log(a.$1));
        return a.$2 + (b.$2 - a.$2) * t;
      }
    }
    return pts.last.$2;
  }

  final gains = <double>[];
  for (final c in kBandFreqs) {
    const n = 9;
    var sum = 0.0;
    for (var k = 0; k < n; k++) {
      sum += at(c * math.pow(2, k / (n - 1) - 0.5));
    }
    final g = (sum / n).clamp(kMinGain, kMaxGain).toDouble();
    gains.add((g * 2).round() / 2);
  }
  return ParsedEq(gains, preamp);
}

const List<double> kIsoFreqs = [
  20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500, 630,
  800, 1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000,
  12500, 16000, 20000,
];

/// Exports the profile as a GraphicEQ line on 1/3-octave points (preamp is
/// folded into the gains).
String formatGraphicEq(EqProfile p) {
  String f(double hz) => hz == hz.roundToDouble() ? hz.round().toString() : '$hz';
  final parts = kIsoFreqs.map(
      (hz) => '${f(hz)} ${(curveAt(p.gains, hz) + p.preamp).toStringAsFixed(1)}');
  return 'GraphicEQ: ${parts.join('; ')}';
}
