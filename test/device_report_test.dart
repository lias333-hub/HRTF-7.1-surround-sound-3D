import 'package:flutter_test/flutter_test.dart';

import 'package:directional_audio/device_report.dart';

Map<String, dynamic> sample({int sdk = 34, bool withEq = true}) => {
      'manufacturer': 'samsung',
      'model': 'SM-J730F',
      'release': '9',
      'sdk': sdk,
      'abis': ['armeabi-v7a', 'armeabi'],
      'sampleRate': '48000',
      'framesPerBuffer': '192',
      'outputs': [
        {'type': 2, 'name': 'Built-in speaker'},
        {'type': 4, 'name': ''},
      ],
      'effects': [
        {'name': 'Equalizer', 'implementor': 'The Android Open Source Project', 'type': kFxEqualizer.toUpperCase(), 'uuid': 'u1'},
        {'name': 'Bass Boost', 'implementor': 'AOSP', 'type': kFxBassBoost, 'uuid': 'u2'},
        {'name': 'Virtualizer', 'implementor': 'AOSP', 'type': kFxVirtualizer, 'uuid': 'u3'},
      ],
      'eq': withEq
          ? {
              'bands': 5,
              'minLevel': -1500,
              'maxLevel': 1500,
              'centers': [60.0, 230.0, 910.0, 3600.0, 14000.0],
              'lows': [0.0, 120.0, 460.0, 1800.0, 7000.0],
              'highs': [120.0, 460.0, 1800.0, 7000.0, 20000.0],
            }
          : null,
      'eqError': withEq ? null : 'boom',
    };

void main() {
  test('fromMap parses numbers, lists and the equalizer', () {
    final r = DeviceReport.fromMap(sample());
    expect(r.phone, 'samsung SM-J730F');
    expect(r.androidName, '9 (API 34)');
    expect(r.sampleRate, 48000);
    expect(r.framesPerBuffer, 192);
    expect(r.abis, ['armeabi-v7a', 'armeabi']);
    expect(r.outputs.map((o) => o.toString()).toList(),
        ['Speaker (Built-in speaker)', 'Wired headphones']);
    expect(r.eq!.bands, 5);
    expect(r.eq!.maxMb, 1500);
    expect(r.hasEffect(kFxEqualizer), isTrue); // type compared case-insensitively
    expect(r.hasEffect(kFxLoudness), isFalse);
  });

  test('model that already starts with the maker name is not repeated', () {
    final m = sample()..['manufacturer'] = 'Xiaomi'..['model'] = 'Xiaomi 23129RN51X';
    expect(DeviceReport.fromMap(m).phone, 'Xiaomi 23129RN51X');
  });

  test('capabilities depend on the Android version and the effects list', () {
    Map<String, Capability> caps(int sdk) => {
          for (final c in DeviceReport.fromMap(sample(sdk: sdk)).capabilities()) c.key: c,
        };
    final old = caps(24);
    expect(old['capture']!.state, CapState.needs);
    expect(old['capture']!.version, 10);
    expect(old['dyn']!.state, CapState.needs);
    final p = caps(28);
    expect(p['capture']!.state, CapState.needs);
    expect(p['dyn']!.state, CapState.yes);
    final q = caps(34);
    expect(q['capture']!.state, CapState.consentPlanned); // the phone allows it; the app has not built it
    expect(q['eq']!.state, CapState.yes);
    expect(q['bass']!.state, CapState.yes);
    expect(q['virt']!.state, CapState.yes);
    expect(q['loud']!.state, CapState.no); // not in the effects list
    expect(q['player']!.state, CapState.planned);
  });

  test('dynamics capability follows the native probe when it was reported', () {
    Capability dyn(Map<String, dynamic> m) =>
        DeviceReport.fromMap(m).capabilities().firstWhere((c) => c.key == 'dyn');
    final failed = sample(sdk: 28)..['dynamics'] = {'ok': false, 'error': 'refused'};
    expect(dyn(failed).state, CapState.no);
    expect(DeviceReport.fromMap(failed).toText(), contains('Dynamics Processing: failed (refused)'));
    final fine = sample(sdk: 28)..['dynamics'] = {'ok': true};
    expect(dyn(fine).state, CapState.yes);
    expect(DeviceReport.fromMap(fine).toText(), contains('Dynamics Processing: can be created'));
    // Below Android 9 the probe result is irrelevant.
    final old = sample(sdk: 24)..['dynamics'] = {'ok': false};
    expect(dyn(old).state, CapState.needs);
  });

  test('missing equalizer is reported, not hidden', () {
    final r = DeviceReport.fromMap(sample(withEq: false));
    expect(r.eq, isNull);
    expect(r.capabilities().firstWhere((c) => c.key == 'eq').state, CapState.no);
    expect(r.toText(), contains('Equalizer: unavailable (boom)'));
  });

  test('report text lists bands, effects and capabilities', () {
    final t = DeviceReport.fromMap(sample()).toText();
    expect(t, contains('Equalizer: 5 bands, range ±15 dB'));
    expect(t, contains('Band 0: 0-120 Hz (center 60)'));
    expect(t, contains('Band 4: 7000-20000 Hz (center 14000)'));
    expect(t, contains('Output sample rate: 48000 Hz, buffer: 192 frames'));
    expect(t, contains('Effects (3):'));
    expect(t, contains('capture: possible with user consent (not built into the app yet)'));
    expect(t, contains('loud: not available'));
  });

  test('tolerates missing fields', () {
    final r = DeviceReport.fromMap({'sdk': 30});
    expect(r.sampleRate, isNull);
    expect(r.outputs, isEmpty);
    expect(r.effects, isEmpty);
    expect(r.toText(), contains('Output sample rate: ? Hz'));
  });
}
