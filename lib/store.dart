import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'eq_model.dart';

class StoreData {
  StoreData({
    required this.user,
    required this.working,
    required this.selected,
    required this.enabled,
  });

  final List<EqProfile> user;
  final EqProfile working;
  final String selected;
  final bool enabled;
}

/// Persists profiles and settings. Every read is defensive: bad data falls back to defaults.
class Store {
  static Future<StoreData> load() async {
    final p = await SharedPreferences.getInstance();
    var user = <EqProfile>[];
    try {
      final raw = p.getString('user');
      if (raw != null) {
        final l = jsonDecode(raw);
        if (l is List) {
          user = l.map(EqProfile.fromJson).whereType<EqProfile>().toList();
        }
      }
    } catch (_) {}
    var working = EqProfile.flat();
    try {
      final raw = p.getString('working');
      if (raw != null) working = EqProfile.fromJson(jsonDecode(raw)) ?? working;
    } catch (_) {}
    return StoreData(
      user: user,
      working: working,
      selected: p.getString('selected') ?? 'builtin:flat',
      enabled: p.getBool('enabled') ?? false,
    );
  }

  static Future<void> saveUser(List<EqProfile> l) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('user', jsonEncode(l.map((e) => e.toJson()).toList()));
  }

  static Future<void> saveWorking(EqProfile w, String selected) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('working', jsonEncode(w.toJson()));
    await p.setString('selected', selected);
  }

  static Future<void> saveEnabled(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('enabled', v);
  }

  static Future<String> loadLang() async {
    final p = await SharedPreferences.getInstance();
    return p.getString('lang') ?? 'ar';
  }

  static Future<void> saveLang(String v) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('lang', v);
  }
}
