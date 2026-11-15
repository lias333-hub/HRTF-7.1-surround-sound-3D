import 'package:flutter/material.dart';

import 'eq_screen.dart';
import 'store.dart';
import 'strings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  L10n.lang = await Store.loadLang();
  runApp(const DirectionalApp());
}

class DirectionalApp extends StatefulWidget {
  const DirectionalApp({super.key});

  @override
  State<DirectionalApp> createState() => _DirectionalAppState();
}

class _DirectionalAppState extends State<DirectionalApp> {
  void _toggleLang() {
    setState(() => L10n.lang = L10n.lang == 'ar' ? 'en' : 'ar');
    Store.saveLang(L10n.lang);
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
      home: EqScreen(onToggleLang: _toggleLang),
    );
  }
}
