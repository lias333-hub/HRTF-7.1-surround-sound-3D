import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:directional_audio/engine_screen.dart';
import 'package:directional_audio/eq_screen.dart';
import 'package:directional_audio/strings.dart';

const _channel = MethodChannel('directional/eq');
const _events = MethodChannel('directional/status'); // the EventChannel's own method channel

class _Native {
  final calls = <String>[];
  bool wanted = false;
  bool running = false;
  String notif = 'denied';
  bool battery = false;
  Map<String, dynamic> dp = {'ok': true};

  Map<String, dynamic> get status => {
        'service': running,
        'wanted': wanted,
        'eqKind': 'dynamics',
        'eqEnabled': true,
        'eqBands': 10,
        'fxActive': false,
        'outputs': [
          {'type': 3, 'name': 'Headset'},
        ],
        'error': null,
      };

  Future<Object?> handle(MethodCall c) async {
    calls.add(c.method);
    switch (c.method) {
      case 'status':
        return status;
      case 'notifStatus':
        return notif;
      case 'notifRequest':
        notif = 'granted';
        return notif;
      case 'batteryIgnored':
        return battery;
      case 'svcStart':
        wanted = true;
        running = true;
        return null;
      case 'svcStop':
        wanted = false;
        running = false;
        return null;
      case 'dpStart':
        return dp;
      default:
        return null;
    }
  }
}

Future<void> _pump(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(1080, 4800);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    builder: (c, child) => Directionality(
      textDirection: L10n.rtl ? TextDirection.rtl : TextDirection.ltr,
      child: child!,
    ),
    home: home,
  ));
  await tester.pumpAndSettle();
}

// The screen waits 400 ms after (un)starting the service before it re-reads the status.
Future<void> _afterService(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pumpAndSettle();
}

void main() {
  late _Native native;

  void mock(WidgetTester tester) {
    native = _Native();
    final m = tester.binding.defaultBinaryMessenger;
    m.setMockMethodCallHandler(_channel, native.handle);
    m.setMockMethodCallHandler(_events, (c) async => null);
    addTearDown(() {
      m.setMockMethodCallHandler(_channel, null);
      m.setMockMethodCallHandler(_events, null);
    });
  }

  for (final lang in ['en', 'ar']) {
    testWidgets('EngineScreen: status, service switch, notification and battery buttons ($lang)',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      mock(tester);
      L10n.setPref(lang, 'en');
      await _pump(tester, const EngineScreen());

      expect(find.text(L10n.t('eng_svc_off')), findsOneWidget);
      expect(find.text(L10n.f('eng_eq_on', {'k': L10n.t('kind_dynamics'), 'n': '10'})), findsOneWidget);
      expect(find.textContaining('Wired headset'), findsOneWidget);
      expect(find.text(L10n.t('eng_notif_no')), findsOneWidget);
      expect(find.text(L10n.t('eng_battery_no')), findsOneWidget);

      // Turning the service on first asks for the notification permission, then starts it.
      await tester.tap(find.byType(Switch));
      await _afterService(tester);
      expect(native.calls, containsAllInOrder(['notifStatus', 'notifRequest', 'svcStart']));
      expect(find.text(L10n.t('eng_svc_on')), findsOneWidget);
      expect(find.text(L10n.t('eng_notif_ok')), findsOneWidget);

      await tester.tap(find.byType(Switch));
      await _afterService(tester);
      expect(native.calls, contains('svcStop'));
      expect(find.text(L10n.t('eng_svc_off')), findsOneWidget);

      await tester.tap(find.text(L10n.t('eng_fix')));
      await tester.pumpAndSettle();
      expect(native.calls, contains('batteryRequest'));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('EqScreen: equalizer type is remembered and drives which back end starts', (tester) async {
    SharedPreferences.setMockInitialValues({});
    mock(tester);
    L10n.setPref('en', 'en');
    await _pump(tester, EqScreen(lang: L10n.lang, onLanguage: () {}));

    // Default is the proven system equalizer.
    expect(find.byType(SegmentedButton<String>), findsOneWidget);
    await tester.tap(find.text(L10n.t('type_dynamics')));
    await tester.pumpAndSettle();
    expect((await SharedPreferences.getInstance()).getString('backend'), 'dynamics');

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(native.calls, containsAllInOrder(['dpStart', 'setEnabled', 'dpGains']));
    expect(find.textContaining(L10n.f('status_dyn', {'n': '10'}).split('.').first), findsOneWidget);
    expect(find.text(L10n.t('open_engine')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('EqScreen: forcing dynamics on a phone that refuses shows the error', (tester) async {
    SharedPreferences.setMockInitialValues({'backend': 'dynamics'});
    mock(tester);
    native.dp = {'ok': false, 'error': 'refused by driver'};
    L10n.setPref('en', 'en');
    await _pump(tester, EqScreen(lang: L10n.lang, onLanguage: () {}));

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('refused by driver'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect(tester.takeException(), isNull);
  });
}
