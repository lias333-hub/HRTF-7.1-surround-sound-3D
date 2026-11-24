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

  // v0.4 state
  Map<String, dynamic>? output = {'key': '3|Headset', 'type': 3, 'name': 'Headset'};
  List<Map<String, dynamic>> assignments = [];
  bool locked = false;
  String? bypass;
  String profile = '';
  int switchSeq = 0;
  Map<String, dynamic> sync = {}; // extra fields in the answer to outSync
  final args = <String, Object?>{}; // last arguments seen per method

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
        'profile': profile,
        'switchSeq': switchSeq,
        'locked': locked,
        'bypass': bypass,
        'output': output,
        'assignments': assignments,
      };

  Future<Object?> handle(MethodCall c) async {
    calls.add(c.method);
    args[c.method] = c.arguments;
    switch (c.method) {
      case 'outSync':
        return {...status, ...sync};
      case 'lockSet':
        locked = (c.arguments as Map)['on'] == true;
        return null;
      case 'outAssign':
        final a = c.arguments as Map;
        assignments = [
          ...assignments.where((x) => x['key'] != a['key']),
          {'key': a['key'], 'type': a['type'], 'name': a['name'], 'profile': a['profile']},
        ];
        return null;
      case 'outUnassign':
        assignments = assignments.where((x) => x['key'] != (c.arguments as Map)['key']).toList();
        return null;
      case 'retry':
        bypass = null;
        return null;
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
  tester.view.physicalSize = const Size(1080, 8000);
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

    await tester.tap(find.byType(Switch).first);
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

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(find.text('refused by driver'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch).first).value, isFalse);
    expect(tester.takeException(), isNull);
  });

  // ------------------------------------------------------------------ v0.4: output, lock, bypass

  Future<void> _push(WidgetTester tester, Map<String, dynamic> status) async {
    // What the native side does when its state changes: send a status event through the EventChannel.
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'directional/status',
      const StandardMethodCodec().encodeSuccessEnvelope(status),
      (_) {},
    );
    await tester.pumpAndSettle();
  }

  testWidgets('EqScreen: shows the current output and assigns the selected profile to it', (tester) async {
    SharedPreferences.setMockInitialValues({'backend': 'dynamics'});
    mock(tester);
    L10n.setPref('en', 'en');
    await _pump(tester, EqScreen(lang: L10n.lang, onLanguage: () {}));

    expect(find.textContaining('Wired headset'), findsOneWidget);
    expect(find.text(L10n.t('out_unassigned')), findsOneWidget);
    // The equalizer is off, so there is nothing to apply the profile to yet.
    expect(tester.widget<ButtonStyleButton>(find.widgetWithText(FilledButton, L10n.t('out_assign'))).onPressed,
        isNull);

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(L10n.t('out_assign')));
    await tester.pumpAndSettle();

    final a = native.args['outAssign'] as Map;
    expect(a['key'], '3|Headset');
    expect(a['type'], 3);
    expect(a['profile'], 'builtin:flat');
    expect((a['gains'] as List).length, 10);
    expect(a['levels'], isEmpty); // dynamics needs no levels
    expect(find.text(L10n.f('out_assigned', {'p': L10n.profileName('builtin:flat')})), findsOneWidget);

    await tester.tap(find.text(L10n.t('out_remove')));
    await tester.pumpAndSettle();
    expect((native.args['outUnassign'] as Map)['key'], '3|Headset');
    expect(find.text(L10n.t('out_unassigned')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('EqScreen: the lock switch is sent to the native side', (tester) async {
    SharedPreferences.setMockInitialValues({});
    mock(tester);
    L10n.setPref('en', 'en');
    await _pump(tester, EqScreen(lang: L10n.lang, onLanguage: () {}));

    expect(tester.widget<Switch>(find.byType(Switch).last).value, isFalse);
    await tester.tap(find.byType(Switch).last);
    await tester.pumpAndSettle();
    expect((native.args['lockSet'] as Map)['on'], isTrue);
    expect(tester.widget<Switch>(find.byType(Switch).last).value, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('EqScreen: starting adopts the profile the native side already picked for the output',
      (tester) async {
    SharedPreferences.setMockInitialValues({'backend': 'dynamics', 'enabled': true});
    mock(tester);
    native.profile = 'builtin:bass';
    native.sync = {'switched': true, 'switchSeq': 3, 'profile': 'builtin:bass'};
    L10n.setPref('en', 'en');
    await _pump(tester, EqScreen(lang: L10n.lang, onLanguage: () {}));

    // The saved selection was "flat", but the headset has "bass": that is what gets sent to the equalizer.
    expect((native.args['dpGains'] as Map)['profile'], 'builtin:bass');
    expect(find.text(L10n.profileName('builtin:bass')), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('EqScreen: a live switch by the native side updates the screen, a stale update does not',
      (tester) async {
    SharedPreferences.setMockInitialValues({'backend': 'dynamics', 'enabled': true});
    mock(tester);
    L10n.setPref('en', 'en');
    await _pump(tester, EqScreen(lang: L10n.lang, onLanguage: () {}));
    native.calls.clear();

    await _push(tester, {...native.status, 'profile': 'builtin:treble', 'switchSeq': 1});
    expect(find.text(L10n.profileName('builtin:treble')), findsWidgets);
    expect(native.calls, isNot(contains('dpGains'))); // already applied natively: not sent again

    // The user picks another profile; an older update (same switchSeq) must not undo that.
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(L10n.profileName('builtin:soft')).last);
    await tester.pumpAndSettle();
    await _push(tester, {...native.status, 'profile': 'builtin:treble', 'switchSeq': 1});
    expect((native.args['dpGains'] as Map)['profile'], 'builtin:soft');
    expect(tester.widget<DropdownButton<String>>(find.byType(DropdownButton<String>)).value, 'builtin:soft');
    expect(tester.takeException(), isNull);
  });

  for (final lang in ['en', 'ar']) {
    testWidgets('EqScreen: bypass banner explains why and the retry button asks the native side ($lang)',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      mock(tester);
      native.bypass = 'create_failed';
      L10n.setPref(lang, 'en');
      await _pump(tester, EqScreen(lang: L10n.lang, onLanguage: () {}));

      expect(find.text(L10n.t('byp_title')), findsOneWidget);
      expect(find.text(L10n.t('byp_create')), findsOneWidget);
      await tester.tap(find.text(L10n.t('byp_retry')));
      await tester.pumpAndSettle();
      expect(native.calls, contains('retry'));
      expect(find.text(L10n.t('byp_title')), findsNothing); // the mock cleared it
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('EqScreen: control lost has its own explanation', (tester) async {
    SharedPreferences.setMockInitialValues({});
    mock(tester);
    native.bypass = 'control_lost';
    L10n.setPref('en', 'en');
    await _pump(tester, EqScreen(lang: L10n.lang, onLanguage: () {}));
    expect(find.text(L10n.t('byp_control')), findsOneWidget);
    expect(find.text(L10n.t('byp_create')), findsNothing);
  });

  testWidgets('EngineScreen: profile, lock, bypass and the per-output list', (tester) async {
    SharedPreferences.setMockInitialValues({});
    mock(tester);
    native.profile = 'builtin:bass';
    native.locked = true;
    native.bypass = 'create_failed';
    native.assignments = [
      {'key': '3|Headset', 'type': 3, 'name': 'Headset', 'profile': 'builtin:bass'},
    ];
    L10n.setPref('en', 'en');
    await _pump(tester, const EngineScreen());

    expect(find.text(L10n.f('eng_profile', {'p': L10n.profileName('builtin:bass')})), findsOneWidget);
    expect(find.text(L10n.t('eng_lock_on')), findsOneWidget);
    expect(find.textContaining(L10n.t('byp_title')), findsOneWidget);
    expect(find.text(L10n.t('eng_assign_title')), findsOneWidget);
    expect(find.text(L10n.profileName('builtin:bass')), findsOneWidget); // the list row

    await tester.tap(find.text(L10n.t('byp_retry')));
    await tester.pumpAndSettle();
    expect(native.calls, contains('retry'));

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect((native.args['outUnassign'] as Map)['key'], '3|Headset');
    expect(find.text(L10n.t('eng_assign_none')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
