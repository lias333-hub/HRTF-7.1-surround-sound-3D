import 'package:flutter/material.dart';

import 'effects_screen.dart';
import 'engine.dart';
import 'eq_screen.dart';
import 'language_sheet.dart';
import 'settings_screen.dart';
import 'strings.dart';
import 'tools_screen.dart';

/// Bottom navigation: Equalizer / Effects / Tools / Settings. Tabs keep their state (IndexedStack).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.lang, required this.onPrefChanged});

  /// The resolved language; passed down so every tab rebuilds when it changes.
  final String lang;
  final ValueChanged<String> onPrefChanged;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    // If the user had the background service on and Android killed the app, bring it back now.
    EngineApi.resumeIfWanted();
  }

  Future<void> _openLanguage() async {
    final p = await showLanguageSheet(context);
    if (p != null && p != L10n.pref) widget.onPrefChanged(p);
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.t;
    final lang = widget.lang;
    // One ScaffoldMessenger per tab so a snack bar shows once, above the navigation bar.
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          ScaffoldMessenger(child: EqScreen(lang: lang, onLanguage: _openLanguage)),
          ScaffoldMessenger(child: EffectsScreen(lang: lang)),
          ScaffoldMessenger(child: ToolsScreen(lang: lang)),
          ScaffoldMessenger(child: SettingsScreen(lang: lang, onLanguage: _openLanguage)),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.equalizer), label: t('nav_eq')),
          NavigationDestination(icon: const Icon(Icons.auto_awesome), label: t('nav_fx')),
          NavigationDestination(icon: const Icon(Icons.build_outlined), label: t('nav_tools')),
          NavigationDestination(icon: const Icon(Icons.settings_outlined), label: t('nav_settings')),
        ],
      ),
    );
  }
}
