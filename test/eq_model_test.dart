import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:directional_audio/eq_model.dart';

void main() {
  test('curveAt interpolates in log frequency and is flat outside the bands', () {
    final g = <double>[0, 0, 0, 0, 0, 6, 6, 6, 6, 6];
    expect(curveAt(g, 10), 0);
    expect(curveAt(g, 30000), 6);
    expect(curveAt(g, 1000), closeTo(6, 1e-9));
    expect(curveAt(g, 707), closeTo(3, 0.2)); // halfway (log) between 500 and 1000
  });

  test('deviceLevels: flat is zero, offsets and preamp add, result is clamped', () {
    List<int> run(List<double> gains, double pre, {int max = 1500}) => deviceLevels(
          gains: gains,
          preamp: pre,
          lows: const [0, 120, 480, 1920, 7680],
          highs: const [120, 480, 1920, 7680, 20000],
          centers: const [60, 230, 910, 3600, 14000],
          minMb: -1500,
          maxMb: max,
        );
    expect(run(List.filled(10, 0.0), 0), everyElement(0));
    expect(run(List.filled(10, 6.0), 0), everyElement(600));
    expect(run(List.filled(10, 6.0), -3), everyElement(300));
    expect(run(List.filled(10, 12.0), 0, max: 1000), everyElement(1000));
    expect(run(List.filled(10, -12.0), -12), everyElement(-1500));
  });

  test('parseGraphicEq reads a flat curve and a preamp line', () {
    final r = parseGraphicEq('Preamp: -4.5 dB\nGraphicEQ: 20 0; 1000 0; 20000 0');
    expect(r, isNotNull);
    expect(r!.gains, everyElement(0));
    expect(r.preamp, -4.5);
  });

  test('parseGraphicEq resamples a ramp onto the 10 bands', () {
    final r = parseGraphicEq('GraphicEQ: 20 6; 100 6; 1000 0; 20000 0');
    expect(r, isNotNull);
    expect(r!.gains.first, closeTo(6, 0.6)); // 31 Hz: on the plateau
    expect(r.gains.last, closeTo(0, 0.6)); // 16 kHz: on the flat part
    expect(r.gains.length, 10);
  });

  test('parseGraphicEq rejects text without usable points', () {
    expect(parseGraphicEq('hello world'), isNull);
    expect(parseGraphicEq('GraphicEQ: 20'), isNull);
    expect(parseGraphicEq(''), isNull);
  });

  test('parseGraphicEq ignores 0 Hz and unusable numbers instead of producing NaN (AU-29)', () {
    expect(parseGraphicEq('GraphicEQ: 0 6; 1000 0'), isNull); // only one usable point left
    final r = parseGraphicEq('GraphicEQ: 0 6; 20 3; 20000 0');
    expect(r, isNotNull);
    expect(r!.gains.every((g) => g.isFinite), isTrue);
    expect(parseGraphicEq('GraphicEQ: ${'9' * 400} 6; 20 3; 20000 0')!.gains.every((g) => g.isFinite), isTrue);
  });

  test('headroomPreamp keeps the total boost at 0 dB or less (AU-18)', () {
    const bass = <double>[6, 5, 4, 2, 0, 0, 0, 0, 0, 0];
    expect(headroomPreamp(bass, 0), -6); // +6 dB bass would clip loud music: lowered by 6
    expect(headroomPreamp(List<double>.filled(10, 0), 0), 0); // flat: nothing to do
    expect(headroomPreamp(const <double>[2, 0, 0, 0, 0, 0, 0, 0, 0, 0], -3), -3); // the user's lower value is kept
    expect(headroomPreamp(List<double>.filled(10, 0), 6), 0); // a boost on a flat curve is capped at 0 dB total
    expect(headroomPreamp(List<double>.filled(10, -3), 0), 0);
    expect(headroomPreamp(List<double>.filled(10, -3), 6), 3); // an all-cut curve leaves room up to its own peak
    expect(headroomPreamp(const <double>[], 2), 2);
  });

  test('headroomPreamp: with it, no built-in profile peaks above 0 dB at any preamp', () {
    for (final p in kBuiltInProfiles) {
      for (var pre = kMinGain; pre <= kMaxGain; pre += 1.5) {
        final eff = headroomPreamp(p.gains, pre);
        expect(eff, lessThanOrEqualTo(pre), reason: '${p.name} pre=$pre');
        expect(p.gains.reduce(math.max) + eff, lessThanOrEqualTo(1e-9), reason: '${p.name} pre=$pre');
        expect(eff, inInclusiveRange(kMinGain, kMaxGain), reason: 'stays inside the native range');
      }
    }
  });

  test('format then parse round-trips a smooth profile within 1 dB', () {
    final p = kBuiltInProfiles.firstWhere((e) => e.name == 'builtin:bass');
    final text = formatGraphicEq(p);
    expect(text.startsWith('GraphicEQ: 20 '), isTrue);
    final r = parseGraphicEq(text)!;
    for (var i = 0; i < 10; i++) {
      expect(r.gains[i], closeTo(p.gains[i], 1.0), reason: 'band $i');
    }
  });

  test('profile json round-trip and rejection of bad data', () {
    const p = EqProfile(
        name: 'mine', gains: <double>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10], preamp: -2);
    final back = EqProfile.fromJson(p.toJson())!;
    expect(back.name, 'mine');
    expect(back.gains, p.gains);
    expect(back.preamp, -2);
    expect(EqProfile.fromJson({'name': 'x', 'gains': [1, 2]}), isNull);
    expect(EqProfile.fromJson('nope'), isNull);
  });
}
