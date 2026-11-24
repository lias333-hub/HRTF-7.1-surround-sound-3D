import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:directional_audio/eq_screen.dart';
import 'package:directional_audio/strings.dart';

void main() {
  for (final lang in L10n.languages.map((l) => l.code)) {
    testWidgets('EqScreen renders 10 band sliders + preamp ($lang)', (tester) async {
      SharedPreferences.setMockInitialValues({});
      L10n.setPref(lang, 'en');
      // Tall on purpose: the list is lazy, and longer translations push the bottom rows further down.
      tester.view.physicalSize = const Size(1080, 4800);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        builder: (c, child) => Directionality(
          textDirection: L10n.rtl ? TextDirection.rtl : TextDirection.ltr,
          child: child!,
        ),
        home: EqScreen(lang: L10n.lang, onLanguage: () {}),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(Slider), findsNWidgets(11));
      expect(find.byType(Switch), findsNWidgets(2)); // master switch + profile lock
      expect(find.text(L10n.t('out_title')), findsOneWidget);
      expect(find.text(L10n.t('open_info')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
