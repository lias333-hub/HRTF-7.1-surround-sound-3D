import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'device_info_screen.dart';
import 'device_report.dart';
import 'engine.dart';
import 'engine_screen.dart';
import 'eq_model.dart';
import 'store.dart';
import 'strings.dart';
import 'throttle.dart';

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
  String? _error; // a failure to start or stop (shown until the next success)
  String? _applyError; // the last failed send of the curve to the engine (cleared by the next successful send)
  bool _notOn = false; // the engine refused to switch on (the effect is missing or another app owns it)
  bool _auto = true; // automatic headroom (AU-18)
  String _pref = 'system';

  // A slider reports many changes a second. Sending each one and writing it to the disk is wasteful (AU-26): the
  // send is merged to one every 50 ms and the save to one every 400 ms; lifting the finger flushes both.
  late final Throttle _applyThrottle = Throttle(const Duration(milliseconds: 50), _apply);
  late final Throttle _saveThrottle = Throttle(const Duration(milliseconds: 400), _saveWorking);

  /// The native engine's view: current output, assignments, lock, bypass.
  EngineStatus _st = EngineStatus.none;
  int _seen = 0; // last EngineStatus.switchSeq handled
  StreamSubscription<EngineStatus>? _sub;

  List<EqProfile> get _all => [...kBuiltInProfiles, ..._user];

  @override
  void initState() {
    super.initState();
    _init();
    _sub = EngineApi.stream().listen(_onStatus, onError: (_) {});
    _loadStatus();
  }

  @override
  void dispose() {
    _applyThrottle.cancel();
    _saveThrottle.flush(); // the last position of a slider must not be lost
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    try {
      final s = await EngineApi.status();
      if (mounted) setState(() => _st = s);
    } catch (_) {}
  }

  /// A live update from the native side. When it switched the profile by itself (the output changed while the
  /// engine was running), show that profile here. Only switches count, so a stale update can never undo a choice
  /// the user just made.
  void _onStatus(EngineStatus s) {
    if (!mounted) return;
    setState(() {
      _st = s;
      if (s.bypass == null) _notOn = false; // it recovered (the native side retries by itself)
    });
    if (s.switchSeq > _seen) {
      _seen = s.switchSeq;
      if (_enabled) _adopt(s.profile);
    }
  }

  /// Makes [name] the selected profile without sending it again (the native side already applied it).
  void _adopt(String name) {
    if (name.isEmpty || name == _selected) return;
    final i = _all.indexWhere((e) => e.name == name);
    if (i < 0) return;
    final p = _all[i].copyWith(name: name);
    setState(() {
      _selected = name;
      _working = p;
    });
    Store.saveWorking(p, name);
  }

  Future<void> _syncSlots() async {
    try {
      final st = await EngineApi.status();
      await _engine.resync(st.assignments, _all);
      await _loadStatus();
    } catch (_) {}
  }

  Future<void> _init() async {
    final s = await Store.load();
    final pref = await Store.loadBackend();
    final auto = await Store.loadAutoPreamp();
    _engine.autoPreamp = auto;
    if (!mounted) return;
    setState(() {
      _auto = auto;
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
        // The answer says whether the effect really is on now (AU-13). If not, the switch stays on (it is what the
        // user asked for; the native side keeps retrying) but the screen says so instead of pretending.
        final took = await _engine.setEnabled(true);
        _enabled = true;
        _notOn = !took;
        // Refresh the saved per-output copies, let the native side pick the profile of the current output
        // (it may have changed while the screen was closed), and only then send what is selected.
        await _syncSlots();
        final r = await EngineApi.outputSync();
        _seen = r.switchSeq;
        _adopt(r.profile);
        await _apply();
        await _loadStatus();
      } else {
        await _engine.setEnabled(false);
        _enabled = false;
        _notOn = false;
        _applyError = null;
      }
      if (mounted) setState(() => _error = null);
    } on PlatformException catch (e) {
      _enabled = false;
      _notOn = false;
      if (mounted) setState(() => _error = e.message ?? e.code);
    } on MissingPluginException {
      _enabled = false;
      _notOn = false;
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
      // A send that worked means an old send error no longer describes the present (AU-15).
      if (mounted && _applyError != null) setState(() => _applyError = null);
    } on PlatformException catch (e) {
      if (mounted) setState(() => _applyError = e.message ?? e.code);
    } on MissingPluginException {
      if (mounted) setState(() => _applyError = 'native bridge missing');
    }
  }

  Future<void> _saveWorking() => Store.saveWorking(_working, _selected);

  /// A discrete change (pick a profile, reset, import): applied and saved at once.
  void _edit(EqProfile p) {
    _applyThrottle.cancel();
    _saveThrottle.cancel();
    setState(() => _working = p);
    _saveWorking();
    _apply();
  }

  /// A slider tick: the screen follows at once, the engine and the disk are updated at a calmer pace (AU-26).
  void _editLive(EqProfile p) {
    setState(() => _working = p);
    _applyThrottle.run();
    _saveThrottle.run();
  }

  /// The finger was lifted: send and save the final position now.
  void _editEnd() {
    _applyThrottle.flush();
    _saveThrottle.flush();
  }

  /// Automatic headroom on/off: the engine gets the same curve with a different preamp, so send it again and
  /// refresh the per-output copies (they carry the preamp too).
  Future<void> _setAuto(bool v) async {
    setState(() => _auto = v);
    _engine.autoPreamp = v;
    await Store.saveAutoPreamp(v);
    if (_enabled) {
      await _apply();
      await _syncSlots();
    }
  }

  String _autoText() {
    if (!_auto) return L10n.t('auto_preamp_off');
    final cut = _working.preamp - headroomPreamp(_working.gains, _working.preamp);
    return cut > 0.05
        ? L10n.f('auto_preamp_on', {'db': cut.toStringAsFixed(1)})
        : L10n.t('auto_preamp_none');
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
    if (name == null || name.isEmpty || !mounted) return;
    // "builtin:" names belong to the built-in profiles: a saved one with that prefix could not be deleted and would
    // appear twice in the list (AU-28).
    if (name.startsWith(kBuiltInPrefix)) {
      _snack(L10n.t('name_reserved'));
      return;
    }
    final i = _user.indexWhere((e) => e.name == name);
    if (i >= 0 && !await _confirmReplace(name)) return;
    if (!mounted) return;
    final p = EqProfile(
        name: name, gains: List<double>.of(_working.gains), preamp: _working.preamp);
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
    await _syncSlots(); // an assignment that points at this name now uses the new contents
  }

  Future<bool> _confirmReplace(String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(L10n.f('name_replace', {'n': name})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(L10n.t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(L10n.t('replace'))),
        ],
      ),
    );
    return ok == true;
  }

  void _delete() {
    if (_selected.startsWith(kBuiltInPrefix)) return;
    setState(() => _user.removeWhere((e) => e.name == _selected));
    Store.saveUser(_user);
    _select('builtin:flat');
    _syncSlots(); // assignments that used the deleted profile are removed
  }

  // ------------------------------------------------------------ output assignment, lock, bypass

  Future<void> _assign() async {
    final o = _st.output;
    if (o == null) return;
    try {
      await _engine.assign(o, _working.copyWith(name: _selected));
      await _loadStatus();
    } on PlatformException catch (e) {
      if (mounted) setState(() => _error = e.message ?? e.code);
    }
  }

  Future<void> _unassign(String key) async {
    try {
      await EngineApi.unassign(key);
      await _loadStatus();
    } on PlatformException catch (e) {
      if (mounted) setState(() => _error = e.message ?? e.code);
    }
  }

  Future<void> _setLock(bool on) async {
    try {
      await EngineApi.setLock(on);
      await _loadStatus();
    } on PlatformException catch (e) {
      if (mounted) setState(() => _error = e.message ?? e.code);
    }
  }

  Future<void> _retry() async {
    try {
      await EngineApi.retry();
      await _loadStatus();
    } on PlatformException catch (e) {
      if (mounted) setState(() => _error = e.message ?? e.code);
    }
  }

  Widget _bypassBanner() {
    final scheme = Theme.of(context).colorScheme;
    final t = L10n.t;
    return Card(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.warning_amber_rounded, color: scheme.onErrorContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(t('byp_title'),
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(color: scheme.onErrorContainer)),
              ),
            ]),
            const SizedBox(height: 4),
            Text(t(_st.bypass == 'control_lost' ? 'byp_control' : 'byp_create'),
                style: TextStyle(color: scheme.onErrorContainer)),
            const SizedBox(height: 8),
            FilledButton.tonal(onPressed: _retry, child: Text(t('byp_retry'))),
          ],
        ),
      ),
    );
  }

  Widget _outputCard() {
    final t = L10n.t;
    final small = Theme.of(context).textTheme.bodySmall;
    final o = _st.output;
    Assignment? asg;
    if (o != null) {
      for (final a in _st.assignments) {
        if (a.key == o.key) asg = a;
      }
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t('out_title'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.headphones, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(o == null
                    ? t('out_unknown')
                    : L10n.f('out_now', {'o': OutputEntry(o.type, o.name).toString()})),
              ),
            ]),
            if (o != null) ...[
              const SizedBox(height: 4),
              Text(
                  asg == null
                      ? t('out_unassigned')
                      : L10n.f('out_assigned', {'p': L10n.profileName(asg.profile)}),
                  style: small),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton.tonal(
                    onPressed: _enabled ? _assign : null, child: Text(t('out_assign'))),
                if (asg != null)
                  TextButton(
                      onPressed: () => _unassign(asg!.key), child: Text(t('out_remove'))),
              ]),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(t('out_lock')),
              subtitle: Text(t('out_lock_sub')),
              value: _st.locked,
              onChanged: _setLock,
            ),
            Text(t('out_hint'), style: small),
          ],
        ),
      ),
    );
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

  /// Why the equalizer is not doing what the switch says, or null. Only what is true right now (AU-14/AU-15).
  String? get _problem {
    if (_error != null) return _error;
    if (_applyError != null) return _applyError;
    if (!_enabled) return null;
    if (_notOn) return L10n.t('err_not_on');
    return _st.error;
  }

  String _statusText() {
    final info = _engine.info;
    // "N bands active" would be a lie while the native side reports the sound as unprocessed (AU-14).
    if (_enabled && _st.bypass != null) return L10n.t('byp_title');
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
                onChanged: (v) => _editLive(_working.withGain(i, v)),
                onChangeEnd: (_) => _editEnd(),
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
                    _problem ?? _statusText(),
                    style: (_problem != null || (_enabled && _st.bypass != null))
                        ? TextStyle(color: Theme.of(context).colorScheme.error)
                        : null,
                  ),
                  value: _enabled,
                  onChanged: _setEnabled,
                ),
                if (_st.bypass != null) _bypassBanner(),
                const SizedBox(height: 8),
                _typePicker(),
                const SizedBox(height: 8),
                _outputCard(),
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
                        onChanged: (v) => _editLive(_working.withPreamp(v)),
                        onChangeEnd: (_) => _editEnd(),
                      ),
                    ),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text('${_working.preamp.toStringAsFixed(1)} dB'),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(t('auto_preamp')),
                  subtitle: Text(_autoText()),
                  value: _auto,
                  onChanged: _setAuto,
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
