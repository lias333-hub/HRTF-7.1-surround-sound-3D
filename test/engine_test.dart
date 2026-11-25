import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:directional_audio/engine.dart';
import 'package:directional_audio/eq_model.dart';

const _channel = MethodChannel('directional/eq');

/// Records every native call and lets a test decide what the native side answers.
class _Native {
  final calls = <MethodCall>[];
  Map<String, dynamic> dp = {'ok': true, 'bands': 10};
  Map<String, dynamic> status = {};
  Map<String, dynamic>? log; // answer to logGet

  Future<Object?> handle(MethodCall c) async {
    calls.add(c);
    switch (c.method) {
      case 'status':
        return status;
      case 'dpStart':
        return dp;
      case 'logGet':
        return log;
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

    // the restart is also written to the event log, before the service is started
    expect(await run(true, false), ['status', 'logAdd', 'svcStart']);
    expect(await run(true, true), ['status']);
    expect(await run(false, false), ['status']);
  });

  // ------------------------------------------------------------------ v0.4

  test('apply sends the profile name with the gains (dynamics) and with the levels (system)', () async {
    final d = EqEngine();
    await d.start(pref: 'dynamics');
    await d.apply(EqProfile(name: 'user:x', gains: List<double>.filled(10, 2), preamp: -1));
    final dp = native.calls.lastWhere((c) => c.method == 'dpGains').arguments as Map;
    expect(dp['profile'], 'user:x');
    expect(dp['preamp'], -1);
    expect((dp['gains'] as List).length, 10);

    native.calls.clear();
    final s = EqEngine();
    await s.start(pref: 'system');
    await s.apply(EqProfile.flat('user:y'));
    final sys = native.calls.lastWhere((c) => c.method == 'setLevels').arguments as Map;
    expect(sys['profile'], 'user:y');
    expect((sys['levels'] as List).length, 5);
  });

  test('assign sends the output, the profile and the levels of the running back end', () async {
    const out = (key: '3|Headset', type: 3, name: 'Headset');
    final s = EqEngine();
    await s.start(pref: 'system');
    await s.assign(out, EqProfile(name: 'builtin:bass', gains: List<double>.filled(10, 6)));
    var a = native.calls.lastWhere((c) => c.method == 'outAssign').arguments as Map;
    expect(a['key'], '3|Headset');
    expect(a['type'], 3);
    expect(a['name'], 'Headset');
    expect(a['profile'], 'builtin:bass');
    expect((a['gains'] as List).length, 10);
    expect((a['levels'] as List).length, 5);
    expect((a['levels'] as List).every((x) => x is int && x <= 1500), isTrue);

    final d = EqEngine();
    await d.start(pref: 'dynamics');
    await d.assign(out, EqProfile.flat());
    a = native.calls.lastWhere((c) => c.method == 'outAssign').arguments as Map;
    expect(a['levels'], isEmpty);
  });

  test('resync refreshes assignments whose profile exists and removes the ones whose profile is gone', () async {
    final e = EqEngine();
    await e.start(pref: 'dynamics');
    native.calls.clear();
    await e.resync(
      [
        (key: '3|Headset', type: 3, name: 'Headset', profile: 'user:mine'),
        (key: '8|Buds', type: 8, name: 'Buds', profile: 'user:deleted'),
      ],
      [EqProfile(name: 'user:mine', gains: List<double>.filled(10, 3))],
    );
    expect(native.names, ['outAssign', 'outUnassign']);
    expect((native.calls[0].arguments as Map)['gains'], List<double>.filled(10, 3));
    expect((native.calls[1].arguments as Map)['key'], '8|Buds');
  });

  test('EngineStatus.fromMap reads output, assignments, lock, bypass and switch counters', () {
    final s = EngineStatus.fromMap({
      'service': true,
      'wanted': true,
      'eqKind': 'dynamics',
      'eqEnabled': true,
      'eqBands': 10,
      'fxActive': false,
      'outputs': [
        {'type': 3, 'name': 'Headset'},
      ],
      'profile': 'builtin:bass',
      'switchSeq': 2,
      'switched': true,
      'locked': true,
      'bypass': 'control_lost',
      'output': {'key': '3|Headset', 'type': 3, 'name': 'Headset'},
      'assignments': [
        {'key': '3|Headset', 'type': 3, 'name': 'Headset', 'profile': 'builtin:bass'},
      ],
    });
    expect(s.profile, 'builtin:bass');
    expect(s.switchSeq, 2);
    expect(s.switched, isTrue);
    expect(s.locked, isTrue);
    expect(s.bypass, 'control_lost');
    expect(s.output, (key: '3|Headset', type: 3, name: 'Headset'));
    expect(s.assignments.single.profile, 'builtin:bass');
  });

  test('EngineStatus.fromMap copes with the v0.3 shape (no new fields)', () {
    final s = EngineStatus.fromMap({
      'service': false,
      'wanted': false,
      'eqKind': 'none',
      'eqEnabled': false,
      'eqBands': 0,
      'fxActive': false,
      'outputs': [],
    });
    expect(s.profile, '');
    expect(s.locked, isFalse);
    expect(s.bypass, isNull);
    expect(s.output, isNull);
    expect(s.assignments, isEmpty);
    expect(s.switchSeq, 0);
  });

  test('outputSync returns the native answer including whether it switched', () async {
    native.status = {'eqKind': 'dynamics', 'profile': 'builtin:bass', 'switched': true};
    // the mock answers every unknown call with null, so teach it this one
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (c) async => c.method == 'outSync' ? native.status : null);
    final r = await EngineApi.outputSync();
    expect(r.switched, isTrue);
    expect(r.profile, 'builtin:bass');
  });

  test('retryIfBypassed retries only while the sound is bypassed', () async {
    native.status = {'eqKind': 'dynamics', 'bypass': null};
    await EngineApi.retryIfBypassed();
    expect(native.names, ['status']);

    native.calls.clear();
    native.status = {'eqKind': 'dynamics', 'bypass': 'create_failed'};
    await EngineApi.retryIfBypassed();
    expect(native.names, ['status', 'retry']);
  });
  // ------------------------------------------------------------------ v0.4.1 (event log)

  test('retry says why it was asked (button by default, "app resume" from the shell)', () async {
    await EngineApi.retry();
    expect(native.calls.last.method, 'retry');
    expect(native.calls.last.arguments, {'reason': 'manual'});

    native.calls.clear();
    native.status = {'eqKind': 'dynamics', 'bypass': 'control_lost'};
    await EngineApi.retryIfBypassed();
    expect(native.calls.last.arguments, {'reason': 'app resume'});
  });

  test('eventLog returns the header and the text; clear and logEvent reach the native side', () async {
    native.log = {'header': 'Samsung SM-J730F | Android 9 (API 28) | armeabi-v7a', 'text': 'l1\nl2'};
    final l = await EngineApi.eventLog();
    expect(l.header, startsWith('Samsung SM-J730F'));
    expect(l.text, 'l1\nl2');

    await EngineApi.clearEventLog();
    await EngineApi.logEvent('app', 'hello');
    expect(native.names, ['logGet', 'logClear', 'logAdd']);
    expect(native.calls.last.arguments, {'tag': 'app', 'msg': 'hello'});
  });

  test('eventLog is empty (and does not throw) when the native side is missing or answers nothing', () async {
    final l = await EngineApi.eventLog(); // the mock answers null
    expect((l.header, l.text), ('', ''));

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null); // no handler at all: MissingPluginException
    final m = await EngineApi.eventLog();
    expect((m.header, m.text), ('', ''));
    await EngineApi.clearEventLog();
    await EngineApi.logEvent('app', 'x');
  });
}
