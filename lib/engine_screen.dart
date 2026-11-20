import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'device_report.dart';
import 'engine.dart';
import 'strings.dart';

/// Background service, permissions, battery settings, and a live view of what the native engine is doing.
class EngineScreen extends StatefulWidget {
  const EngineScreen({super.key});

  @override
  State<EngineScreen> createState() => _EngineScreenState();
}

class _EngineScreenState extends State<EngineScreen> with WidgetsBindingObserver {
  EngineStatus _status = EngineStatus.none;
  String _notif = 'na';
  bool _battery = true;
  String? _error;
  StreamSubscription<EngineStatus>? _sub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _sub = EngineApi.stream().listen(
      (s) {
        if (mounted) setState(() => _status = s);
      },
      onError: (_) {},
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    super.dispose();
  }

  // Coming back from the system settings: re-read permission and battery state.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  String _msg(Object e) => e is PlatformException ? (e.message ?? e.code) : '$e';

  Future<void> _refresh() async {
    try {
      final s = await EngineApi.status();
      final n = await EngineApi.notifStatus();
      final b = await EngineApi.batteryIgnored();
      if (!mounted) return;
      setState(() {
        _status = s;
        _notif = n;
        _battery = b;
        _error = null;
      });
    } on MissingPluginException {
      if (mounted) setState(() => _error = 'native bridge missing');
    } on PlatformException catch (e) {
      if (mounted) setState(() => _error = _msg(e));
    }
  }

  Future<void> _toggleService(bool on) async {
    try {
      if (on) {
        // Asking first means the notification can actually be shown; the service works either way.
        if (await EngineApi.notifStatus() == 'denied') await EngineApi.notifRequest();
        await EngineApi.svcStart();
      } else {
        await EngineApi.svcStop();
      }
      // Give the service a moment to report that it started or stopped.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await _refresh();
    } catch (e) {
      if (mounted) setState(() => _error = _msg(e));
    }
  }

  Future<void> _allowNotif() async {
    try {
      await EngineApi.notifRequest();
    } catch (_) {}
    await _refresh();
  }

  Future<void> _fixBattery() async {
    try {
      await EngineApi.batteryRequest();
    } catch (e) {
      if (mounted) setState(() => _error = _msg(e));
    }
  }

  String _kind(String k) => k == 'dynamics'
      ? L10n.t('kind_dynamics')
      : k == 'system'
          ? L10n.t('kind_system')
          : k;

  List<Widget> _statusLines(TextStyle? small) {
    final s = _status;
    final eq = s.eqKind == 'none'
        ? L10n.t('eng_eq_none')
        : L10n.f(s.eqEnabled ? 'eng_eq_on' : 'eng_eq_off', {
            'k': _kind(s.eqKind),
            'n': '${s.eqBands}',
          });
    final outs = s.outputs.map((o) => OutputEntry(o.type, o.name).toString()).toList();
    return [
      _line(s.service ? Icons.check_circle_outline : Icons.pause_circle_outline,
          L10n.t(s.service ? 'eng_svc_on' : 'eng_svc_off')),
      _line(Icons.equalizer, eq),
      _line(Icons.auto_awesome, L10n.t(s.fxActive ? 'eng_fx_on' : 'eng_fx_off')),
      _line(Icons.headphones,
          '${L10n.t('eng_out')}: ${outs.isEmpty ? L10n.t('di_none') : outs.join(' · ')}'),
      if (s.error != null) _line(Icons.error_outline, L10n.f('eng_err', {'e': s.error!}), error: true),
    ];
  }

  Widget _line(IconData icon, String text, {bool error = false}) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: error ? scheme.error : null),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: error ? TextStyle(color: scheme.error) : null),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.t;
    final small = Theme.of(context).textTheme.bodySmall;
    return Scaffold(
      appBar: AppBar(title: Text(t('eng_title'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: SwitchListTile(
              title: Text(t('eng_service')),
              subtitle: Text(t('eng_service_sub')),
              value: _status.wanted,
              onChanged: _toggleService,
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t('eng_status'), style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  ..._statusLines(small),
                ],
              ),
            ),
          ),
          if (_notif != 'na')
            Card(
              child: ListTile(
                leading: const Icon(Icons.notifications_outlined),
                title: Text(t('eng_notif')),
                subtitle: Text(t(_notif == 'granted' ? 'eng_notif_ok' : 'eng_notif_no')),
                trailing: _notif == 'granted'
                    ? null
                    : FilledButton.tonal(onPressed: _allowNotif, child: Text(t('eng_allow'))),
              ),
            ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.battery_saver_outlined),
              title: Text(t('eng_battery')),
              subtitle: Text(t(_battery ? 'eng_battery_ok' : 'eng_battery_no')),
              trailing: _battery
                  ? null
                  : FilledButton.tonal(onPressed: _fixBattery, child: Text(t('eng_fix'))),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(_error!,
                  style: small?.copyWith(color: Theme.of(context).colorScheme.error)),
            ),
          const SizedBox(height: 8),
          Text(t('eng_note'), style: small),
        ],
      ),
    );
  }
}
