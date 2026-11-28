import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'device_report.dart';
import 'strings.dart';

/// Everything this phone reports about its audio stack, so any user can see the REAL number of
/// equalizer bands and which effects exist, and copy the report to share it.
class DeviceInfoScreen extends StatefulWidget {
  const DeviceInfoScreen({super.key});

  @override
  State<DeviceInfoScreen> createState() => _DeviceInfoScreenState();
}

class _DeviceInfoScreenState extends State<DeviceInfoScreen> {
  DeviceReport? _r;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await DeviceReport.load();
      if (mounted) setState(() => _r = r);
    } catch (e) {
      final msg = e is PlatformException ? (e.message ?? e.code) : '$e';
      if (mounted) setState(() => _error = msg);
    }
  }

  Future<void> _copy() async {
    final r = _r;
    if (r == null) return;
    await Clipboard.setData(ClipboardData(text: r.toText()));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(L10n.t('di_copied'))));
  }

  /// Label + value. Values are technical text (model names, Hz, ABIs): always left-to-right.
  Widget _kv(String k, String v) {
    final muted = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 2, child: Text(k, style: muted)),
          Expanded(
            flex: 3,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Text(v, textAlign: L10n.rtl ? TextAlign.right : TextAlign.left),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> children) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ...children,
            ],
          ),
        ),
      );

  String _capText(Capability c) {
    switch (c.state) {
      case CapState.yes:
        return L10n.t('cap_yes');
      case CapState.consent:
        return L10n.t('cap_consent');
      case CapState.no:
        return L10n.t('cap_no');
      case CapState.needs:
        return L10n.f('cap_needs', {'v': '${c.version}'});
      case CapState.planned:
        return L10n.t('cap_planned');
      case CapState.consentPlanned:
        return L10n.t('cap_consent_planned');
    }
  }

  Widget _capRow(Capability c) {
    final cs = Theme.of(context).colorScheme;
    final good = c.state == CapState.yes || c.state == CapState.consent;
    // Not built yet: neither a tick nor a cross.
    final later = c.state == CapState.planned || c.state == CapState.consentPlanned;
    final color = good ? cs.primary : (later ? cs.onSurfaceVariant : cs.error);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            good ? Icons.check_circle_outline : (later ? Icons.schedule : Icons.cancel_outlined),
            size: 20,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(L10n.t('cap_${c.key}'))),
          const SizedBox(width: 12),
          Flexible(
            child: Text(_capText(c), style: TextStyle(color: color), textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }

  List<Widget> _eqRows(DeviceReport r) {
    final e = r.eq;
    if (e == null) {
      return [
        Text(
          L10n.f('di_no_eq', {'e': r.eqError ?? '?'}),
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ];
    }
    return [
      Text(
        L10n.f('di_eq_bands', {'n': '${e.bands}'}),
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      Text(L10n.f('di_eq_range', {'r': (e.maxMb / 100).toStringAsFixed(0)})),
      const SizedBox(height: 8),
      for (var i = 0; i < e.bands; i++)
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: L10n.rtl ? Alignment.centerRight : Alignment.centerLeft,
            child: Text(
              L10n.f('di_band', {
                'i': '${i + 1}',
                'lo': '${e.lows[i].round()}',
                'hi': '${e.highs[i].round()}',
                'c': '${e.centers[i].round()}',
              }),
            ),
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.t;
    final r = _r;
    return Scaffold(
      appBar: AppBar(
        title: Text(t('di_title')),
        actions: [
          if (r != null)
            IconButton(
              icon: const Icon(Icons.copy),
              tooltip: t('di_copy'),
              onPressed: _copy,
            ),
        ],
      ),
      body: _error != null
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                L10n.f('di_error', {'e': _error!}),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            )
          : r == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _section(t('di_eq'), _eqRows(r)),
                    _section(t('di_cap'), [for (final c in r.capabilities()) _capRow(c)]),
                    _section(t('di_phone'), [
                      _kv(t('di_phone'), r.phone),
                      _kv(t('di_android'), r.androidName),
                      _kv(t('di_abi'), r.abis.join(', ')),
                    ]),
                    _section(t('di_audio'), [
                      _kv(t('di_rate'), r.sampleRate == null ? '?' : '${r.sampleRate} Hz'),
                      _kv(t('di_buffer'),
                          r.framesPerBuffer == null ? '?' : '${r.framesPerBuffer}'),
                      _kv(
                        t('di_outputs'),
                        r.outputs.isEmpty ? t('di_none') : r.outputs.join('\n'),
                      ),
                    ]),
                    Card(
                      child: ExpansionTile(
                        title: Text('${t('di_effects')} (${r.effects.length})'),
                        children: [
                          for (final f in r.effects)
                            ListTile(
                              dense: true,
                              title: Directionality(
                                textDirection: TextDirection.ltr,
                                child: Text(f.name),
                              ),
                              subtitle: Directionality(
                                textDirection: TextDirection.ltr,
                                child: Text(f.implementor),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: _copy,
                      icon: const Icon(Icons.copy),
                      label: Text(t('di_copy')),
                    ),
                  ],
                ),
    );
  }
}
