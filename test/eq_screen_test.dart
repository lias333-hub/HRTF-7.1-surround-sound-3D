import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:directional_audio/eq_screen.dart';
import 'package:directional_audio/strings.dart';

void main() {
  for (final lang in ['ar', 'en']) {
    testWidgets('EqScreen renders 10 band sliders + preamp ($lang)', (tester) async {
      SharedPreferences.setMockInitialValues({});
      L10n.lang = lang;
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        builder: (c, child) => Directionality(
          textDirection: L10n.rtl ? TextDirection.rtl : TextDirection.ltr,
          child: child!,
        ),
        home: EqScreen(onToggleLang: () {}),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(Slider), findsNWidgets(11));
      expect(find.byType(Switch), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
