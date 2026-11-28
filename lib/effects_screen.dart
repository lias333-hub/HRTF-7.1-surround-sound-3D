import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'engine.dart';
import 'store.dart';
import 'strings.dart';
import 'throttle.dart';

class _FxSetting {
  _FxSetting(this.on, this.v);
  bool on;
  int v;
}

/// Android's built-in bass boost, virtualizer and loudness enhancer, shown only when the device offers them.
class EffectsScreen extends StatefulWidget {
  const EffectsScreen({super.key, required this.lang});

  /// Only here so the screen rebuilds when the language changes.
  final String lang;

  @override
  State<EffectsScreen> createState() => _EffectsScreenState();
}

class _EffectsScreenState extends State<EffectsScreen> {
  final _engine = FxEngine();
  final Map<String, _FxSetting> _s = {
    'bass': _FxSetting(false, 500),
    'virt': _FxSetting(false, 500),
    'loud': _FxSetting(false, 300),
  };
  Map<String, FxStatus> _status = {};
  bool _loaded = false;
  String? _error;

  /// The native side says the sound is not being processed although something is switched on (AU-12).
  String? _bypass;
  StreamSubscription<EngineStatus>? _sub;

  // Slider ticks are merged (AU-26): one send every 50 ms, one disk write every 400 ms, both flushed on release.
  final Set<String> _pending = {};
  late final Throttle _applyThrottle = Throttle(const Duration(milliseconds: 50), _applyPending);
  late final Throttle _saveThrottle = Throttle(const Duration(milliseconds: 400), _save);

  @override
  void initState() {
    super.initState();
    _init();
    _sub = EngineApi.stream().listen((s) {
      if (mounted && s.bypass != _bypass) setState(() => _bypass = s.bypass);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _applyThrottle.cancel();
    _saveThrottle.flush();
    _sub?.cancel();
    super.dispose();
  }

  String _msg(Object e) => e is PlatformException ? (e.message ?? e.code) : '$e';

  Future<void> _init() async {
    final saved = await Store.loadFx();
    for (final k in FxEngine.keys) {
      final m = saved[k];
      if (m is Map) {
        _s[k]!.on = m['on'] == true;
        final v = m['v'];
        if (v is num) _s[k]!.v = v.round();
      }
    }
    try {
      // Only ask which effects the phone has. Creating an effect takes its control away from other equalizer apps
      // (only one app controls an effect type), so an effect is created when the user wants it: here only the ones
      // that were left switched on, later the one the user switches on (AU-25).
      _status = await _engine.probe();
      final wanted = [
        for (final k in FxEngine.keys)
          if (_status[k]?.ok == true && _s[k]!.on) k,
      ];
      if (wanted.isNotEmpty) {
        _status = await _engine.start(only: wanted);
        for (final k in wanted) {
          if (_status[k]?.ok == true) await _engine.set(k, true, _s[k]!.v);
        }
      }
    } catch (e) {
      _error = _msg(e);
    }
    if (mounted) setState(() => _loaded = true);
  }

  void _save() => Store.saveFx({
        for (final e in _s.entries) e.key: {'on': e.value.on, 'v': e.value.v},
      });

  Future<void> _apply(String key) async {
    try {
      await _engine.set(key, _s[key]!.on, _s[key]!.v);
      if (mounted && _error != null) setState(() => _error = null);
    } catch (e) {
      if (mounted) setState(() => _error = _msg(e));
    }
  }

  /// Creates the one effect the user just asked for (the ones already created are kept). False when the phone
  /// refused: the switch goes back off and the reason is shown.
  Future<bool> _ensure(String key) async {
    String? why;
    try {
      _status = await _engine.start(only: [key]);
      if (_status[key]?.ok != true) why = _status[key]?.error ?? L10n.t('fx_unsupported');
    } catch (e) {
      why = _msg(e);
    }
    if (why == null) {
      if (mounted) setState(() {}); // the real instance may differ from the probe (for example: no strength control)
      return true;
    }
    _s[key]!.on = false;
    _save();
    if (mounted) setState(() => _error = why);
    return false;
  }

  Future<void> _toggle(String key, bool on) async {
    setState(() => _s[key]!.on = on);
    _applyThrottle.flush(); // a slider move still waiting must not be lost
    _save();
    if (on && !await _ensure(key)) return;
    await _apply(key);
  }

  void _slide(String key, int v) {
    setState(() => _s[key]!.v = v);
    _saveThrottle.run();
    if (_s[key]!.on) {
      _pending.add(key);
      _applyThrottle.run();
    }
  }

  void _slideEnd() {
    _applyThrottle.flush();
    _saveThrottle.flush();
  }

  void _applyPending() {
    final keys = _pending.toList();
    _pending.clear();
    for (final k in keys) {
      _apply(k);
    }
  }

  Widget _bypassNote() {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(L10n.t('byp_title'),
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(color: scheme.onErrorContainer)),
            const SizedBox(height: 4),
            Text(L10n.t(_bypass == 'control_lost' ? 'byp_control' : 'byp_create'),
                style: TextStyle(color: scheme.onErrorContainer)),
            const SizedBox(height: 8),
            FilledButton.tonal(
                onPressed: () => EngineApi.retry(), child: Text(L10n.t('byp_retry'))),
          ],
        ),
      ),
    );
  }

  Widget _card({
    required String key,
    required String title,
    required double max,
    required String Function(int) label,
    required String sliderLabel,
    String? note,
  }) {
    final st = _status[key];
    final s = _s[key]!;
    final available = st?.ok == true;
    final small = Theme.of(context).textTheme.bodySmall;
    final showSlider = available && (st!.strengthSupported || key == 'loud');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(title),
              subtitle: available ? null : Text(L10n.t('fx_unsupported')),
              value: available && s.on,
              onChanged: available ? (v) => _toggle(key, v) : null,
            ),
            if (showSlider)
              Row(
                children: [
                  Text(sliderLabel),
                  Expanded(
                    child: Slider(
                      min: 0,
                      max: max,
                      divisions: 20,
                      value: s.v.toDouble().clamp(0.0, max).toDouble(),
                      onChanged: (v) => _slide(key, v.round()),
                      onChangeEnd: (_) => _slideEnd(),
                    ),
                  ),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(label(s.v)),
                  ),
                ],
              ),
            if (note != null) Text(note, style: small),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.t;
    return Scaffold(
      appBar: AppBar(title: Text(t('nav_fx'))),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(t('fx_intro'), style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                if (_bypass != null) _bypassNote(),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      L10n.f('fx_error', {'e': _error!}),
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                _card(
                  key: 'bass',
                  title: t('fx_bass'),
                  max: 1000,
                  sliderLabel: t('fx_strength'),
                  label: (v) => '${(v / 10).round()}%',
                ),
                _card(
                  key: 'virt',
                  title: t('fx_virt'),
                  max: 1000,
                  sliderLabel: t('fx_strength'),
                  label: (v) => '${(v / 10).round()}%',
                  note: t('fx_virt_note'),
                ),
                _card(
                  key: 'loud',
                  title: t('fx_loud'),
                  max: 1500,
                  sliderLabel: t('fx_gain'),
                  label: (v) => '${(v / 100).toStringAsFixed(1)} dB',
                  note: t('fx_loud_note'),
                ),
              ],
            ),
    );
  }
}
