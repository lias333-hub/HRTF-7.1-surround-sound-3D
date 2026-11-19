import 'package:flutter/material.dart';

import 'app_info.dart';
import 'strings.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.lang, required this.onLanguage});

  /// Only here so the screen rebuilds when the language changes.
  final String lang;
  final VoidCallback onLanguage;

  @override
  Widget build(BuildContext context) {
    final t = L10n.t;
    final small = Theme.of(context).textTheme.bodyMedium;
    final current = L10n.pref == 'system'
        ? '${t('set_system')} (${L10n.nameOf(L10n.lang)})'
        : L10n.nameOf(L10n.pref);
    return Scaffold(
      appBar: AppBar(title: Text(t('set_title'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.language),
              title: Text(t('set_language')),
              subtitle: Text(current),
              onTap: onLanguage,
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t('set_limits_title'),
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(t('set_limits'), style: small),
                ],
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(t('set_about')),
              subtitle: Directionality(
                textDirection: TextDirection.ltr,
                child: Align(
                  alignment: L10n.rtl ? Alignment.centerRight : Alignment.centerLeft,
                  child: Text('Directional Audio · ${t('set_version')} $kAppVersion'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
