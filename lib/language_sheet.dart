import 'package:flutter/material.dart';

import 'strings.dart';

/// Bottom sheet with "system language" and every supported language written in its own name.
/// Returns the chosen preference ('system' or a code), or null if dismissed.
Future<String?> showLanguageSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      Widget tile(String code, String title, {IconData? icon}) {
        final selected = L10n.pref == code;
        return ListTile(
          leading: Icon(icon ?? Icons.language),
          title: Text(title),
          trailing: selected ? const Icon(Icons.check) : null,
          selected: selected,
          onTap: () => Navigator.pop(ctx, code),
        );
      }

      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(L10n.t('set_lang_title'),
                  style: Theme.of(ctx).textTheme.titleMedium),
            ),
            tile('system', L10n.t('set_system'), icon: Icons.smartphone),
            for (final l in L10n.languages) tile(l.code, l.name),
          ],
        ),
      );
    },
  );
}
