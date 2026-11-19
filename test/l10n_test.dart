import 'package:flutter_test/flutter_test.dart';

import 'package:directional_audio/strings.dart';

Set<String> _placeholders(String s) =>
    RegExp(r'\{(\w+)\}').allMatches(s).map((m) => m.group(1)!).toSet();

void main() {
  final en = L10n.all['en']!;

  test('every supported language has a table', () {
    for (final l in L10n.languages) {
      expect(L10n.all.containsKey(l.code), isTrue, reason: l.code);
    }
  });

  for (final l in L10n.languages) {
    test('${l.code}: same keys and placeholders as English, no empty values', () {
      final m = L10n.all[l.code]!;
      expect(m.keys.toSet(), en.keys.toSet(), reason: 'keys differ in ${l.code}');
      for (final k in en.keys) {
        expect(m[k]!.trim(), isNotEmpty, reason: '${l.code}/$k is empty');
        expect(_placeholders(m[k]!), _placeholders(en[k]!),
            reason: 'placeholders differ in ${l.code}/$k');
      }
    });
  }

  test('setPref resolves system / explicit / unknown values', () {
    L10n.setPref('system', 'fr');
    expect([L10n.pref, L10n.lang], ['system', 'fr']);
    L10n.setPref('system', 'de'); // unsupported system language -> English
    expect([L10n.pref, L10n.lang], ['system', 'en']);
    L10n.setPref('tr', 'ar');
    expect([L10n.pref, L10n.lang], ['tr', 'tr']);
    L10n.setPref('xx', 'ar'); // unknown saved value -> treated as system
    expect([L10n.pref, L10n.lang], ['system', 'ar']);
    L10n.setPref('ar', 'en');
    expect(L10n.rtl, isTrue);
    L10n.setPref('en', 'ar');
    expect(L10n.rtl, isFalse);
  });

  test('t falls back to the key, f fills placeholders', () {
    L10n.setPref('en', 'en');
    expect(L10n.t('no_such_key'), 'no_such_key');
    expect(L10n.f('di_eq_bands', {'n': '5'}), 'Real bands: 5');
    expect(L10n.profileName('builtin:flat'), 'Flat');
    expect(L10n.profileName('My profile'), 'My profile');
  });
}
