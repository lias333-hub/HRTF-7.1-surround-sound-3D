import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_info.dart';
import 'core_bench.dart';
import 'engine.dart';
import 'strings.dart';

/// "Core speed test": runs the native DSP benchmark on this phone and shows one technical line per case.
/// The numbers decide how heavy the sound processing may be (for example direct or FFT convolution), so after
/// a run the person copies the lines and sends them over. Each line is also written to the event log.
class CoreBenchCard extends StatefulWidget {
  const CoreBenchCard({super.key});

  @override
  State<CoreBenchCard> createState() => _CoreBenchCardState();
}

class _CoreBenchCardState extends State<CoreBenchCard> {
  CoreInfo? _info;
  final List<String> _rows = [];
  bool _running = false;
  bool _done = false;
  bool _copied = false;
  int _step = 0;

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    final i = await CoreApi.info();
    if (mounted) setState(() => _info = i);
  }

  Future<void> _run() async {
    final info = _info;
    if (_running || info == null || !info.loaded) return;
    setState(() {
      _running = true;
      _done = false;
      _copied = false;
      _step = 0;
      _rows.clear();
    });
    await EngineApi.logEvent('bench', 'start | ${info.line}');
    for (var i = 0; i < kBenchSuite.length; i++) {
      if (!mounted) return;
      setState(() => _step = i + 1);
      final c = kBenchSuite[i];
      final r = await CoreApi.bench(c);
      final line = r.line(c);
      await EngineApi.logEvent('bench', line);
      if (!mounted) return;
      setState(() => _rows.add(line));
    }
    if (mounted) {
      setState(() {
        _running = false;
        _done = true;
      });
    }
  }

  Future<void> _copy() async {
    final head = (await EngineApi.eventLog()).header;
    final text = 'Directional Audio $kAppVersion | $head\n${_info?.line ?? ''}\n${_rows.join('\n')}';
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.t;
    final small = Theme.of(context).textTheme.bodySmall;
    final info = _info;
    final error = Theme.of(context).colorScheme.error;
    const mono = TextStyle(fontFamily: 'monospace', fontSize: 11, height: 1.35);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.speed),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(t('cb_title'), style: Theme.of(context).textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(t('cb_hint'), style: small),
            const SizedBox(height: 8),
            if (info != null && info.loaded) ...[
              Directionality(
                textDirection: TextDirection.ltr,
                child: SelectableText(info.line, style: mono),
              ),
              if (!info.optimized) ...[
                const SizedBox(height: 4),
                Text(t('cb_not_opt'), style: small?.copyWith(color: error)),
              ],
            ],
            if (info != null && !info.loaded)
              Text(L10n.f('cb_unavail', {'e': info.error}), style: small?.copyWith(color: error)),
            const SizedBox(height: 8),
            if (_running) ...[
              LinearProgressIndicator(value: (_step - 1) / kBenchSuite.length),
              const SizedBox(height: 4),
              Text(
                L10n.f('cb_running', {'i': '$_step', 'n': '${kBenchSuite.length}'}),
                style: small,
              ),
              const SizedBox(height: 8),
            ],
            if (_rows.isNotEmpty)
              // Result lines are English technical text: always left-to-right, also in Arabic.
              Directionality(
                textDirection: TextDirection.ltr,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(_rows.join('\n'), style: mono),
                ),
              ),
            if (_done) ...[
              const SizedBox(height: 8),
              Text(t('cb_est'), style: small),
              const SizedBox(height: 4),
              Text(t('cb_done'), style: small),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: (_running || info == null || !info.loaded) ? null : _run,
                  icon: const Icon(Icons.play_arrow),
                  label: Text(t('cb_run')),
                ),
                if (_rows.isNotEmpty)
                  FilledButton.tonalIcon(
                    onPressed: _copy,
                    icon: Icon(_copied ? Icons.check : Icons.copy),
                    label: Text(t(_copied ? 'log_copied' : 'log_copy')),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
