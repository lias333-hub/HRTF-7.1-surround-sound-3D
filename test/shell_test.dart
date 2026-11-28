import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:directional_audio/shell.dart';
import 'package:directional_audio/strings.dart';

const _channel = MethodChannel('directional/eq');

/// A fake native side: a 5-band equalizer, bass boost + virtualizer present, loudness enhancer refused.
Future<Object?> _fakeNative(MethodCall call) async {
  switch (call.method) {
    case 'deviceInfo':
      return {
        'manufacturer': 'Google',
        'model': 'Pixel 6',
        'release': '14',
        'sdk': 34,
        'abis': ['x86_64'],
        'sampleRate': '48000',
        'framesPerBuffer': '192',
        'outputs': [
          {'type': 2, 'name': 'Speaker'},
        ],
        'effects': [
          {'name': 'Equalizer', 'implementor': 'AOSP', 'type': '0bed4300-ddd6-11db-8f34-0002a5d5c51b', 'uuid': 'a'},
        ],
        'eq': {
          'bands': 5,
          'minLevel': -1500,
          'maxLevel': 1500,
          'centers': [60.0, 230.0, 910.0, 3600.0, 14000.0],
          'lows': [0.0, 120.0, 460.0, 1800.0, 7000.0],
          'highs': [120.0, 460.0, 1800.0, 7000.0, 20000.0],
        },
        'eqError': null,
      };
    case 'fxProbe': // which effects exist, without creating any
    case 'fxStart':
      return {
        'bass': {'ok': true, 'strengthSupported': true},
        'virt': {'ok': true, 'strengthSupported': true},
        'loud': {'ok': false, 'error': 'refused'},
      };
    default:
      return null;
  }
}

void main() {
  for (final lang in ['en', 'ar']) {
    testWidgets('shell: four tabs, effects availability, device info, language sheet ($lang)',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, _fakeNative);
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, null));
      L10n.setPref(lang, 'en');
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      String? picked;
      await tester.pumpWidget(MaterialApp(
        builder: (c, child) => Directionality(
          textDirection: L10n.rtl ? TextDirection.rtl : TextDirection.ltr,
          child: child!,
        ),
        home: HomeShell(lang: L10n.lang, onPrefChanged: (p) => picked = p),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(NavigationDestination), findsNWidgets(4));

      // Effects: bass boost and virtualizer available, loudness refused by the device.
      await tester.tap(find.text(L10n.t('nav_fx')));
      await tester.pumpAndSettle();
      expect(find.byType(Switch), findsNWidgets(3));
      expect(find.byType(Slider), findsNWidgets(2));
      expect(find.text(L10n.t('fx_unsupported')), findsOneWidget);

      // Tools -> device info shows the real number of bands.
      await tester.tap(find.text(L10n.t('nav_tools')));
      await tester.pumpAndSettle();
      expect(find.text(L10n.t('tool_test')), findsOneWidget);
      await tester.tap(find.text(L10n.t('tool_info')));
      await tester.pumpAndSettle();
      expect(find.text(L10n.f('di_eq_bands', {'n': '5'})), findsOneWidget);
      expect(find.text(L10n.f('di_eq_range', {'r': '15'})), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      // Settings -> language sheet lists every language, picking one reports it.
      await tester.tap(find.text(L10n.t('nav_settings')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(L10n.t('set_language')));
      await tester.pumpAndSettle();
      for (final l in L10n.languages) {
        expect(find.text(l.name), findsWidgets, reason: l.code);
      }
      await tester.tap(find.text('Français'));
      await tester.pumpAndSettle();
      expect(picked, 'fr');

      expect(tester.takeException(), isNull);
    });
  }

  group('Effects tab creates nothing until the user wants it (AU-25)', () {
    late List<MethodCall> calls;

    Future<void> open(WidgetTester tester, Map<String, Object> prefs) async {
      SharedPreferences.setMockInitialValues(prefs);
      calls = [];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (c) async {
        calls.add(c);
        return _fakeNative(c);
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null));
      L10n.setPref('en', 'en');
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: HomeShell(lang: L10n.lang, onPrefChanged: (_) {})));
      await tester.pumpAndSettle();
      await tester.tap(find.text(L10n.t('nav_fx')));
      await tester.pumpAndSettle();
    }

    List<String> names() => calls.map((c) => c.method).toList();

    testWidgets('opening the app only asks which effects exist; the first switch creates just that one',
        (tester) async {
      await open(tester, {});
      expect(names(), contains('fxProbe'));
      expect(names(), isNot(contains('fxStart'))); // nothing created, nothing taken from other apps
      expect(find.byType(Slider), findsNWidgets(2)); // availability is still shown

      calls.clear();
      await tester.tap(find.byType(Switch).first); // bass boost
      await tester.pumpAndSettle();
      final start = calls.firstWhere((c) => c.method == 'fxStart');
      expect(start.arguments, {'names': ['bass']});
      final set = calls.firstWhere((c) => c.method == 'fxSet');
      expect((set.arguments as Map)['name'], 'bass');
      expect((set.arguments as Map)['on'], isTrue);
      expect(names().indexOf('fxStart'), lessThan(names().indexOf('fxSet')));
      expect(tester.takeException(), isNull);
    });

    testWidgets('an effect left switched on is created again at start, and only that one', (tester) async {
      await open(tester, {
        'fx': jsonEncode({
          'virt': {'on': true, 'v': 400},
        }),
      });
      final start = calls.firstWhere((c) => c.method == 'fxStart');
      expect(start.arguments, {'names': ['virt']});
      final set = calls.firstWhere((c) => c.method == 'fxSet');
      expect((set.arguments as Map)['name'], 'virt');
      expect((set.arguments as Map)['value'], 400);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a slider drag sends once after the finger lifts (AU-26)', (tester) async {
      await open(tester, {
        'fx': jsonEncode({
          'bass': {'on': true, 'v': 500},
        }),
      });
      calls.clear();
      final g = await tester.startGesture(tester.getCenter(find.byType(Slider).first));
      for (var i = 0; i < 12; i++) {
        await g.moveBy(const Offset(12, 0)); // no time passes between the moves
      }
      expect(names(), isNot(contains('fxSet')));
      await g.up();
      await tester.pumpAndSettle();
      expect(names().where((n) => n == 'fxSet'), hasLength(1));
      expect(tester.takeException(), isNull);
    });
  });
}
