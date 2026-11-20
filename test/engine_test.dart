import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:directional_audio/engine.dart';
import 'package:directional_audio/eq_model.dart';

const _channel = MethodChannel('directional/eq');

/// Records every native call and lets a test decide what the native side answers.
class _Native {
  final calls = <MethodCall>[];
  Map<String, dynamic> dp = {'ok': true, 'bands': 10};

  Future<Object?> handle(MethodCall c) async {
    calls.add(c);
    switch (c.method) {
      case 'dpStart':
        return dp;
      case 'start':
        return {
          'bands': 5,
          'minLevel': -1500,
          'maxLevel': 1500,
          'centers': [60.0, 230.0, 910.0, 3600.0, 14000.0],
          'lows': [0.0, 120.0, 460.0, 1800.0, 7000.0],
          'highs': [120.0, 460.0, 1800.0, 7000.0, 20000.0],
        };
      default:
        return null;
    }
  }

  List<String> get names => calls.map((c) => c.method).toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Native native;

  setUp(() {
    native = _Native();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, native.handle);
  });
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, null));

  test("pref 'system' never touches Dynamics Processing", () async {
    final e = EqEngine();
    expect(await e.start(pref: 'system'), EqBackend.system);
    expect(native.names, ['start']);
    expect(e.bands, 5);
  });

  test("pref 'auto' uses dynamics when it works, with one band per UI band", () async {
    final e = EqEngine();
    expect(await e.start(pref: 'auto'), EqBackend.dynamics);
    expect(native.names, ['dpStart']);
    expect(native.calls.first.arguments['centers'], kBandFreqs);
    expect(e.bands, kBandFreqs.length);
    expect(e.info, isNull);
  });

  test("pref 'auto' falls back to the system equalizer when dynamics fails", () async {
    native.dp = {'ok': false, 'error': 'needs Android 9+'};
    final e = EqEngine();
    expect(await e.start(pref: 'auto'), EqBackend.system);
    expect(native.names, ['dpStart', 'start']);
    expect(e.info!.bands, 5);
  });

  test("pref 'dynamics' reports the failure instead of hiding it", () async {
    native.dp = {'ok': false, 'error': 'refused'};
    final e = EqEngine();
    await expectLater(
      e.start(pref: 'dynamics'),
      throwsA(isA<PlatformException>().having((x) => x.message, 'message', 'refused')),
    );
    expect(native.names, ['dpStart']);
    expect(e.backend, isNull);
  });

  test('apply sends dB gains + preamp to dynamics, millibel levels to the system equalizer', () async {
    final p = EqProfile.flat().withGain(0, 6).withPreamp(-3);
    final d = EqEngine();
    await d.start(pref: 'dynamics');
    await d.apply(p);
    final last = native.calls.last;
    expect(last.method, 'dpGains');
    expect((last.arguments['gains'] as List).first, 6.0);
    expect(last.arguments['preamp'], -3.0);

    native.calls.clear();
    final s = EqEngine();
    await s.start(pref: 'system');
    await s.apply(p);
    expect(native.calls.last.method, 'setLevels');
    expect((native.calls.last.arguments['levels'] as List).length, 5);
  });

  test('apply does nothing before start, and stop forgets the back end', () async {
    final e = EqEngine();
    await e.apply(EqProfile.flat());
    expect(native.calls, isEmpty);
    await e.start(pref: 'dynamics');
    await e.stop();
    expect(e.backend, isNull);
    expect(native.names.last, 'stop');
  });

  test('EngineStatus.fromMap parses the native snapshot and tolerates gaps', () {
    final s = EngineStatus.fromMap({
      'service': true,
      'wanted': true,
      'eqKind': 'dynamics',
      'eqEnabled': true,
      'eqBands': 10,
      'fxActive': false,
      'outputs': [
        {'type': 8, 'name': 'Buds'},
      ],
      'error': 'boom',
    });
    expect([s.service, s.wanted, s.eqKind, s.eqEnabled, s.eqBands, s.fxActive],
        [true, true, 'dynamics', true, 10, false]);
    expect(s.outputs.single, (type: 8, name: 'Buds'));
    expect(s.error, 'boom');

    final empty = EngineStatus.fromMap({});
    expect([empty.service, empty.wanted, empty.eqKind, empty.eqBands], [false, false, 'none', 0]);
    expect(empty.outputs, isEmpty);
  });

  test('resumeIfWanted restarts the service only when it was wanted and is not running', () async {
    Future<Object?> status(bool wanted, bool service) async => {'wanted': wanted, 'service': service};
    Future<List<String>> run(bool wanted, bool service) async {
      native.calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (c) async {
        native.calls.add(c);
        return c.method == 'status' ? await status(wanted, service) : null;
      });
      await EngineApi.resumeIfWanted();
      return native.names;
    }

    expect(await run(true, false), ['status', 'svcStart']);
    expect(await run(true, true), ['status']);
    expect(await run(false, false), ['status']);
  });
}
