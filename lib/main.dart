import 'package:flutter/material.dart';

import 'shell.dart';
import 'store.dart';
import 'strings.dart';

String _systemLangCode() => WidgetsBinding.instance.platformDispatcher.locale.languageCode;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  L10n.setPref(await Store.loadLang(), _systemLangCode());
  runApp(const DirectionalApp());
}

class DirectionalApp extends StatefulWidget {
  const DirectionalApp({super.key});

  @override
  State<DirectionalApp> createState() => _DirectionalAppState();
}

class _DirectionalAppState extends State<DirectionalApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The phone's language changed while the app is open: follow it if the user chose "system language".
  @override
  void didChangeLocales(List<Locale>? locales) {
    if (L10n.pref == 'system') {
      setState(() => L10n.setPref('system', _systemLangCode()));
    }
  }

  void _setPref(String pref) {
    setState(() => L10n.setPref(pref, _systemLangCode()));
    Store.saveLang(pref);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Directional Audio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C5CE7),
          brightness: Brightness.dark,
        ),
      ),
      builder: (context, child) => Directionality(
        textDirection: L10n.rtl ? TextDirection.rtl : TextDirection.ltr,
        child: child!,
      ),
      home: HomeShell(lang: L10n.lang, onPrefChanged: _setPref),
    );
  }
}
