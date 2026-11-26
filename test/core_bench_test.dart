import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:directional_audio/app_info.dart';
import 'package:directional_audio/core_bench.dart';
import 'package:directional_audio/core_bench_card.dart';
import 'package:directional_audio/strings.dart';

const _channel = MethodChannel('directional/eq');

const _infoOk = 'ok=1;version=0.1.0;arch=armeabi-v7a;bits=32;neonCompiled=1;simdOk=1;opt=1';

String _benchOk(int kernel, int taps, int block) =>
    'ok=1;kernel=$kernel;taps=$taps;block=$block;blockMs=10.000;flatNs=125000;mmacs=${kernel == 2 ? '850.5' : '0.0'};'
    'rtBlocks=200;rtMisses=0;cpuNs=800000;p50Ns=820000;p99Ns=1500000;maxNs=2100000;loadPct=8.00;loadP99Pct=15.00;'
    'maxErr=8.900e-08';

class _Native {
  final calls = <String>[];
  final benchArgs = <Map<dynamic, dynamic>>[];
  final log = <String>[];
  String info = _infoOk;
  bool busyOnSecond = false;

  Future<Object?> handle(MethodCall c) async {
    calls.add(c.method);
    switch (c.method) {
      case 'coreInfo':
        return {'raw': info, 'abis': ['armeabi-v7a', 'armeabi']};
      case 'coreBench':
        final a = c.arguments as Map<dynamic, dynamic>;
        benchArgs.add(a);
        if (busyOnSecond && benchArgs.length == 2) return 'ok=0;error=another benchmark is already running';
        return _benchOk(a['kernel'] as int, a['taps'] as int, a['block'] as int);
      case 'logAdd':
        final a = c.arguments as Map<dynamic, dynamic>;
        log.add('[${a['tag']}] ${a['msg']}');
        return null;
      case 'logGet':
        return {'header': 'Samsung SM-J730F | Android 9 (API 28) | armeabi-v7a', 'text': ''};
      default:
        return null;
    }
  }
}

void main() {
  late _Native native;

  void mock(WidgetTester? tester) {
    native = _Native();
    final m = (tester?.binding ?? TestWidgetsFlutterBinding.ensureInitialized()).defaultBinaryMessenger;
    m.setMockMethodCallHandler(_channel, native.handle);
    addTearDown(() => m.setMockMethodCallHandler(_channel, null));
  }

  group('parsing', () {
    test('parseKv keeps key=value pairs and skips junk', () {
      expect(parseKv('ok=1;a=b;junk;=x;c=d=e; f = g '), {'ok': '1', 'a': 'b', 'c': 'd=e', 'f': 'g'});
      expect(parseKv(''), isEmpty);
    });

    test('CoreInfo: a loaded core, a failed load, no answer', () {
      final ok = CoreInfo.fromMap({'raw': _infoOk, 'abis': ['armeabi-v7a']});
      expect(ok.loaded, isTrue);
      expect([ok.version, ok.arch, ok.bits], ['0.1.0', 'armeabi-v7a', 32]);
      expect([ok.neonCompiled, ok.simdOk, ok.optimized], [true, true, true]);
      expect(ok.line, 'core 0.1.0 | armeabi-v7a 32-bit | neon=1 simd=1 opt=1 | phone abis=armeabi-v7a');

      final bad = CoreInfo.fromMap({'raw': 'ok=0;error=UnsatisfiedLinkError: no dacore', 'abis': ['x86_64']});
      expect(bad.loaded, isFalse);
      expect(bad.error, contains('UnsatisfiedLinkError'));
      expect(bad.abis, ['x86_64']);

      expect(CoreInfo.fromMap(const {}).loaded, isFalse);
    });

    test('an unoptimised build is reported', () {
      final i = CoreInfo.fromMap({'raw': 'ok=1;version=0.1.0;arch=x86_64;bits=64;neonCompiled=0;simdOk=1;opt=0'});
      expect(i.loaded, isTrue);
      expect(i.optimized, isFalse);
    });

    test('BenchResult.parse reads every field and builds the report line', () {
      final r = BenchResult.parse(_benchOk(2, 256, 480));
      expect(r.ok, isTrue);
      expect([r.kernel, r.taps, r.block], [2, 256, 480]);
      expect(r.flatNs, 125000);
      expect(r.mmacs, 850.5);
      expect([r.rtBlocks, r.rtMisses], [200, 0]);
      expect(r.loadPct, 8.0);
      expect(r.loadP99Pct, 15.0);
      expect(r.maxErr, closeTo(8.9e-8, 1e-12));
      expect(r.surroundEstimatePct, 32.0); // 4 x the 4-filter load

      final line = r.line(const BenchCase(kBenchFir4, 256, 480));
      expect(line, startsWith('fir4 256t blk=480 | flat 125.0 us (851 MMAC/s)'));
      expect(line, contains('paced cpu 8.0% p99 15.0%'));
      expect(line, contains('miss 0/200'));
      expect(line, contains('7.1~32%'));
      expect(line, endsWith('err 8.9e-8'));
    });

    test('only the 4-filter case estimates 7.1, the equalizer cases do not', () {
      final eq = BenchResult.parse(_benchOk(3, 10, 480));
      expect(eq.surroundEstimatePct, isNull);
      expect(eq.line(const BenchCase(kBenchSosD, 10, 480)), isNot(contains('7.1~')));
    });

    test('a failed answer becomes a FAILED line, not an exception', () {
      final r = BenchResult.parse('ok=0;error=taps out of range');
      expect(r.ok, isFalse);
      expect(r.line(const BenchCase(kBenchFir4, 9999, 480)), 'fir4 9999t: FAILED taps out of range');
      expect(BenchResult.parse('').ok, isFalse);
    });

    test('the suite covers the equalizer in float and double and three FIR lengths at 10 ms blocks', () {
      expect(kBenchSuite.map((c) => c.name),
          ['eq float 10b', 'eq double 10b', 'fir4 128t', 'fir4 256t', 'fir4 512t']);
      expect(kBenchSuite.every((c) => c.block == 480), isTrue);
    });
  });

  group('CoreApi', () {
    test('info and bench talk to the native side with the case as arguments', () async {
      mock(null);
      final i = await CoreApi.info();
      expect(i.loaded, isTrue);
      expect(i.abis, ['armeabi-v7a', 'armeabi']);
      final r = await CoreApi.bench(const BenchCase(kBenchFir4, 128, 480), rtMs: 1500);
      expect(r.ok, isTrue);
      expect(native.benchArgs.single, {'kernel': 2, 'taps': 128, 'block': 480, 'rtMs': 1500});
    });

    test('without a native side nothing throws', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final i = await CoreApi.info();
      expect(i.loaded, isFalse);
      expect(i.error, 'no native side');
      final r = await CoreApi.bench(const BenchCase(kBenchSos, 10, 480));
      expect(r.ok, isFalse);
      expect(r.error, 'no native side');
    });
  });

  group('CoreBenchCard', () {
    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        builder: (c, child) => Directionality(
          textDirection: L10n.rtl ? TextDirection.rtl : TextDirection.ltr,
          child: child!,
        ),
        home: const Scaffold(body: SingleChildScrollView(child: CoreBenchCard())),
      ));
      await tester.pumpAndSettle();
    }

    for (final lang in ['en', 'ar']) {
      testWidgets('runs every case in order, logs each line and copies a report ($lang)', (tester) async {
        mock(tester);
        String? copied;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async {
          if (c.method == 'Clipboard.setData') copied = (c.arguments as Map)['text'] as String?;
          return null;
        });
        addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
        L10n.setPref(lang, 'en');
        await pump(tester);

        expect(find.text(L10n.t('cb_title')), findsOneWidget);
        expect(find.textContaining('core 0.1.0 | armeabi-v7a 32-bit'), findsOneWidget);
        expect(find.text(L10n.t('cb_not_opt')), findsNothing);

        await tester.tap(find.text(L10n.t('cb_run')));
        await tester.pumpAndSettle();

        expect(native.benchArgs.map((a) => [a['kernel'], a['taps'], a['block'], a['rtMs']]), [
          [1, 10, 480, kBenchRtMs],
          [3, 10, 480, kBenchRtMs],
          [2, 128, 480, kBenchRtMs],
          [2, 256, 480, kBenchRtMs],
          [2, 512, 480, kBenchRtMs],
        ]);
        expect(native.log.length, 6); // "start" + one line per case
        expect(native.log.first, startsWith('[bench] start | core 0.1.0'));
        expect(native.log[4], startsWith('[bench] fir4 256t blk=480'));
        expect(find.text(L10n.t('cb_done')), findsOneWidget);
        expect(find.text(L10n.t('cb_est')), findsOneWidget);

        await tester.tap(find.text(L10n.t('log_copy')));
        await tester.pumpAndSettle();
        expect(copied, startsWith('Directional Audio $kAppVersion | Samsung SM-J730F | Android 9'));
        final lines = copied!.split('\n');
        expect(lines.length, 7); // header, core line, 5 cases
        expect(lines[1], startsWith('core 0.1.0'));
        expect(lines.last, startsWith('fir4 512t'));
        expect(find.text(L10n.t('log_copied')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a core that did not load says why and cannot be run', (tester) async {
      mock(tester);
      native.info = 'ok=0;error=UnsatisfiedLinkError: dlopen failed';
      L10n.setPref('en', 'en');
      await pump(tester);

      expect(find.textContaining('UnsatisfiedLinkError'), findsOneWidget);
      final run = tester.widget<ButtonStyleButton>(find.ancestor(
        of: find.text(L10n.t('cb_run')),
        matching: find.bySubtype<ButtonStyleButton>(),
      ));
      expect(run.onPressed, isNull);
      expect(native.benchArgs, isEmpty);
    });

    testWidgets('an unoptimised build shows the warning', (tester) async {
      mock(tester);
      native.info = 'ok=1;version=0.1.0;arch=x86_64;bits=64;neonCompiled=0;simdOk=1;opt=0';
      L10n.setPref('en', 'en');
      await pump(tester);
      expect(find.text(L10n.t('cb_not_opt')), findsOneWidget);
    });

    testWidgets('a case that fails is shown as FAILED and the rest still run', (tester) async {
      mock(tester);
      native.busyOnSecond = true;
      L10n.setPref('en', 'en');
      await pump(tester);

      await tester.tap(find.text(L10n.t('cb_run')));
      await tester.pumpAndSettle();
      expect(native.benchArgs.length, 5);
      expect(native.log[2], '[bench] eq double 10b: FAILED another benchmark is already running');
      expect(find.text(L10n.t('cb_done')), findsOneWidget);
    });

    test('every language has the new texts, with the placeholders the code fills', () {
      for (final l in L10n.languages) {
        final m = L10n.all[l.code]!;
        expect(m['cb_running'], allOf(contains('{i}'), contains('{n}')), reason: l.code);
        expect(m['cb_unavail'], contains('{e}'), reason: l.code);
      }
    });
  });
}
