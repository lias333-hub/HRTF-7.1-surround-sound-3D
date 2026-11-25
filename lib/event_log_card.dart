import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_info.dart';
import 'engine.dart';
import 'strings.dart';

/// Shows the engine's rolling event log with copy / clear / refresh. After a test on a real phone the person copies
/// it and sends it over, so what the engine did is on record instead of being remembered.
class EventLogCard extends StatefulWidget {
  const EventLogCard({super.key});

  @override
  State<EventLogCard> createState() => _EventLogCardState();
}

class _EventLogCardState extends State<EventLogCard> {
  /// Only the newest lines are shown on screen; "copy" always takes the whole log.
  static const shownLines = 40;

  String _header = '';
  String _text = '';
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final l = await EngineApi.eventLog();
      if (!mounted) return;
      setState(() {
        _header = l.header;
        _text = l.text;
        _copied = false;
      });
    } catch (_) {}
  }

  String get _full => 'Directional Audio $kAppVersion | $_header\n$_text';

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _full));
    if (mounted) setState(() => _copied = true);
  }

  Future<void> _clear() async {
    await EngineApi.clearEventLog();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.t;
    final lines = _text.isEmpty ? <String>[] : _text.split('\n');
    final shown = lines.length > shownLines ? lines.sublist(lines.length - shownLines) : lines;
    final small = Theme.of(context).textTheme.bodySmall;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t('log_title'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(t('log_hint'), style: small),
            const SizedBox(height: 8),
            Container(
              height: 220,
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              // Log lines are English technical text: always left-to-right, also in Arabic.
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: shown.isEmpty
                    ? Text(t('log_empty'), style: small)
                    : SingleChildScrollView(
                        reverse: true,
                        child: SelectableText(
                          shown.join('\n'),
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 11, height: 1.3),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _copy,
                  icon: Icon(_copied ? Icons.check : Icons.copy),
                  label: Text(t(_copied ? 'log_copied' : 'log_copy')),
                ),
                OutlinedButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  label: Text(t('log_refresh')),
                ),
                OutlinedButton.icon(
                  onPressed: _clear,
                  icon: const Icon(Icons.clear_all),
                  label: Text(t('log_clear')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
