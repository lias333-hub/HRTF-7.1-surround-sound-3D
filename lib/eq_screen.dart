import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'device_info_screen.dart';
import 'engine.dart';
import 'engine_screen.dart';
import 'eq_model.dart';
import 'store.dart';
import 'strings.dart';

class EqScreen extends StatefulWidget {
  const EqScreen({super.key, required this.lang, required this.onLanguage});

  /// Only here so the screen rebuilds when the language changes.
  final String lang;

  /// Opens the language picker.
  final VoidCallback onLanguage;

  @override
  State<EqScreen> createState() => _EqScreenState();
}

class _EqScreenState extends State<EqScreen> {
  final _engine = EqEngine();
  EqProfile _working = EqProfile.flat();
  String _selected = 'builtin:flat';
  List<EqProfile> _user = [];
  bool _enabled = false;
  bool _loaded = false;
  String? _error;
  String _pref = 'system';

  List<EqProfile> get _all => [...kBuiltInProfiles, ..._user];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final s = await Store.load();
    final pref = await Store.loadBackend();
    if (!mounted) return;
    setState(() {
      _user = s.user;
      _working = s.working;
      _selected = _all.any((e) => e.name == s.selected)
          ? s.selected
          : 'builtin:flat';
      _pref = pref;
      _loaded = true;
    });
    if (s.enabled) await _setEnabled(true);
  }

  Future<void> _setEnabled(bool on) async {
    try {
      if (on) {
        await _engine.start(pref: _pref);
        await _engine.setEnabled(true);
        _enabled = true;
        await _apply();
      } else {
        await _engine.setEnabled(false);
        _enabled = false;
      }
      if (mounted) setState(() => _error = null);
    } on PlatformException catch (e) {
      _enabled = false;
      if (mounted) setState(() => _error = e.message ?? e.code);
    } on MissingPluginException {
      _enabled = false;
      if (mounted) setState(() => _error = 'native bridge missing');
    }
    Store.saveEnabled(_enabled);
  }

  /// Switching the back end while the equalizer is on rebuilds it with the new one.
  Future<void> _setPref(String p) async {
    if (p == _pref) return;
    setState(() => _pref = p);
    await Store.saveBackend(p);
    if (_enabled) {
      try {
        await _engine.stop();
      } catch (_) {}
      await _setEnabled(true);
    } else if (mounted) {
      setState(() {});
    }
  }

  Future<void> _apply() async {
    if (!_enabled) return;
    try {
      await _engine.apply(_working);
    } on PlatformException catch (e) {
      if (mounted) setState(() => _error = e.message ?? e.code);
    }
  }

  void _edit(EqProfile p) {
    setState(() => _working = p);
    Store.saveWorking(p, _selected);
    _apply();
  }

  void _select(String key) {
    final p = _all.firstWhere((e) => e.name == key);
    setState(() => _selected = key);
    _edit(p.copyWith(name: key));
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _saveAs() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.t('save_as')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(labelText: L10n.t('name')),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(L10n.t('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: Text(L10n.t('save'))),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final p = EqProfile(
        name: name, gains: List<double>.of(_working.gains), preamp: _working.preamp);
    final i = _user.indexWhere((e) => e.name == name);
    setState(() {
      if (i >= 0) {
        _user[i] = p;
      } else {
        _user.add(p);
      }
      _selected = name;
      _working = p;
    });
    await Store.saveUser(_user);
    await Store.saveWorking(p, name);
  }

  void _delete() {
    if (_selected.startsWith(kBuiltInPrefix)) return;
    setState(() => _user.removeWhere((e) => e.name == _selected));
    Store.saveUser(_user);
    _select('builtin:flat');
  }

  Future<void> _import() async {
    final ctrl = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.t('import_title')),
        content: TextField(
          controller: ctrl,
          maxLines: 6,
          decoration: InputDecoration(hintText: L10n.t('import_hint')),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final d = await Clipboard.getData('text/plain');
              ctrl.text = d?.text ?? '';
            },
            child: Text(L10n.t('paste')),
          ),
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(L10n.t('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: Text(L10n.t('import'))),
        ],
      ),
    );
    if (text == null || text.trim().isEmpty) return;
    final parsed = parseGraphicEq(text);
    if (parsed == null) {
      _snack(L10n.t('import_bad'));
      return;
    }
    _edit(EqProfile(name: _selected, gains: parsed.gains, preamp: parsed.preamp));
    _snack(L10n.t('import_ok'));
  }

  Future<void> _export() async {
    await Clipboard.setData(ClipboardData(text: formatGraphicEq(_working)));
    _snack(L10n.t('copied'));
  }

  String _freqLabel(double hz) =>
      hz >= 1000 ? '${(hz / 1000).round()}k' : hz.round().toString();

  String _statusText() {
    final info = _engine.info;
    if (_enabled && _engine.backend == EqBackend.dynamics) {
      return L10n.f('status_dyn', {'n': '${_engine.bands}'});
    }
    if (_enabled && info != null) {
      return L10n.f('status_ok', {
        'n': '${info.bands}',
        'r': '${(info.maxMb / 100).round()}',
      });
    }
    return L10n.t('tip_global');
  }

  Widget _typePicker() {
    final t = L10n.t;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t('eq_type'), style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: 'system', label: Text(t('type_system'))),
              ButtonSegment(value: 'dynamics', label: Text(t('type_dynamics'))),
              ButtonSegment(value: 'auto', label: Text(t('type_auto'))),
            ],
            selected: {_pref},
            onSelectionChanged: (s) => _setPref(s.first),
          ),
        ),
        const SizedBox(height: 4),
        Text(t('type_hint'), style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  Widget _band(int i) {
    final small = Theme.of(context).textTheme.labelSmall;
    return Expanded(
      child: Column(
        children: [
          Text(_working.gains[i].toStringAsFixed(1), style: small),
          Expanded(
            child: RotatedBox(
              quarterTurns: 3,
              child: Slider(
                min: kMinGain,
                max: kMaxGain,
                divisions: 48,
                value: _working.gains[i],
                onChanged: (v) => _edit(_working.withGain(i, v)),
              ),
            ),
          ),
          Text(_freqLabel(kBandFreqs[i]), style: small),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.t;
    return Scaffold(
      appBar: AppBar(
        title: Text(t('app_title')),
        actions: [
          IconButton(
            icon: const Icon(Icons.translate),
            tooltip: t('set_language'),
            onPressed: widget.onLanguage,
          ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(t('effect_on')),
                  subtitle: Text(
                    _error ?? _statusText(),
                    style: _error == null
                        ? null
                        : TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                  value: _enabled,
                  onChanged: _setEnabled,
                ),
                const SizedBox(height: 8),
                _typePicker(),
                const SizedBox(height: 16),
                Text(t('profile'), style: Theme.of(context).textTheme.labelLarge),
                DropdownButton<String>(
                  isExpanded: true,
                  value: _selected,
                  items: [
                    for (final p in _all)
                      DropdownMenuItem(
                          value: p.name, child: Text(L10n.profileName(p.name))),
                  ],
                  onChanged: (v) {
                    if (v != null) _select(v);
                  },
                ),
                const SizedBox(height: 12),
                // Frequencies always run low -> high, left to right, in both languages.
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: SizedBox(
                    height: 260,
                    child: Row(children: [for (var i = 0; i < kBandFreqs.length; i++) _band(i)]),
                  ),
                ),
                Row(
                  children: [
                    Text(t('preamp')),
                    Expanded(
                      child: Slider(
                        min: kMinGain,
                        max: kMaxGain,
                        divisions: 48,
                        value: _working.preamp,
                        onChanged: (v) => _edit(_working.withPreamp(v)),
                      ),
                    ),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text('${_working.preamp.toStringAsFixed(1)} dB'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                        onPressed: () => _edit(EqProfile.flat(_selected)),
                        icon: const Icon(Icons.restart_alt),
                        label: Text(t('reset'))),
                    OutlinedButton.icon(
                        onPressed: _saveAs,
                        icon: const Icon(Icons.save_outlined),
                        label: Text(t('save_as'))),
                    OutlinedButton.icon(
                        onPressed: _import,
                        icon: const Icon(Icons.file_download_outlined),
                        label: Text(t('import'))),
                    OutlinedButton.icon(
                        onPressed: _export,
                        icon: const Icon(Icons.file_upload_outlined),
                        label: Text(t('export'))),
                    if (!_selected.startsWith(kBuiltInPrefix))
                      OutlinedButton.icon(
                          onPressed: _delete,
                          icon: const Icon(Icons.delete_outline),
                          label: Text(t('delete'))),
                  ],
                ),
                const SizedBox(height: 16),
                Text(t('note_bands'), style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => const DeviceInfoScreen()),
                      ),
                      icon: const Icon(Icons.info_outline),
                      label: Text(t('open_info')),
                    ),
                    TextButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => const EngineScreen()),
                      ),
                      icon: const Icon(Icons.settings_input_component),
                      label: Text(t('open_engine')),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
