import 'package:flutter/services.dart';

import 'eq_model.dart';
import 'strings.dart';

/// What the device's hardware equalizer reports (frequencies in Hz, levels in millibels).
class DeviceInfo {
  const DeviceInfo({
    required this.bands,
    required this.minMb,
    required this.maxMb,
    required this.centers,
    required this.lows,
    required this.highs,
  });

  final int bands;
  final int minMb;
  final int maxMb;
  final List<double> centers;
  final List<double> lows;
  final List<double> highs;

  factory DeviceInfo.fromMap(Map<dynamic, dynamic> m) {
    List<double> list(String k) =>
        (m[k] as List).map((e) => (e as num).toDouble()).toList();
    return DeviceInfo(
      bands: m['bands'] as int,
      minMb: m['minLevel'] as int,
      maxMb: m['maxLevel'] as int,
      centers: list('centers'),
      lows: list('lows'),
      highs: list('highs'),
    );
  }
}

/// Which android.media.audiofx implementation is doing the equalizing.
enum EqBackend { system, dynamics }

/// What the user may choose: 'system', 'dynamics' (Android 9+) or 'auto' (dynamics if it can be created).
const kBackendPrefs = ['system', 'dynamics', 'auto'];

/// One audio output: its saved-table key ("type|name"), the AudioDeviceInfo type and the product name.
typedef OutputRef = ({String key, int type, String name});

/// "This output uses that saved profile".
typedef Assignment = ({String key, int type, String name, String profile});

/// Equalizer bridge. Two interchangeable back ends sit behind it:
/// the system [EqBackend.system] equalizer (few bands, works on old Android) and
/// [EqBackend.dynamics] (one real band per UI band plus a limiter, Android 9+).
class EqEngine {
  static const _ch = MethodChannel('directional/eq');

  /// The system equalizer's real bands (only set while [backend] is [EqBackend.system]).
  DeviceInfo? info;
  EqBackend? backend;

  /// Auto headroom (AU-18): the preamp that is sent is lowered so the curve's peak cannot go above 0 dB
  /// (see [headroomPreamp]). Profiles keep the preamp the user chose; only what goes to the engine changes.
  bool autoPreamp = true;

  /// The preamp (dB) that really goes to the engine for [p].
  double preampFor(EqProfile p) => autoPreamp ? headroomPreamp(p.gains, p.preamp) : p.preamp;

  /// How many real bands the running back end has.
  int get bands => backend == EqBackend.dynamics ? kBandFreqs.length : (info?.bands ?? 0);

  /// Creates the equalizer (disabled) and returns the back end that was actually used.
  /// With pref 'dynamics' a failure is thrown so it is visible; with 'auto' it falls back to the system one.
  Future<EqBackend> start({String pref = 'system'}) async {
    if (pref == 'dynamics' || pref == 'auto') {
      final r = await _ch.invokeMethod<Map<dynamic, dynamic>>('dpStart', {'centers': kBandFreqs});
      if (r?['ok'] == true) {
        info = null;
        return backend = EqBackend.dynamics;
      }
      if (pref == 'dynamics') {
        throw PlatformException(
            code: 'DP_FAILED', message: '${r?['error'] ?? 'Dynamics Processing unavailable'}');
      }
    }
    final m = await _ch.invokeMethod<Map<dynamic, dynamic>>('start', {'session': 0});
    info = DeviceInfo.fromMap(m!);
    return backend = EqBackend.system;
  }

  /// Millibel levels for the system equalizer's real bands; empty when another back end is running.
  List<int> _levels(EqProfile p) {
    final i = info;
    if (backend != EqBackend.system || i == null) return const [];
    return deviceLevels(
      gains: p.gains,
      preamp: preampFor(p),
      lows: i.lows,
      highs: i.highs,
      centers: i.centers,
      minMb: i.minMb,
      maxMb: i.maxMb,
    );
  }

  /// Sends the profile to whichever back end is running. The profile's name travels along so the native
  /// side always knows which saved profile is applied.
  Future<void> apply(EqProfile p) async {
    if (backend == EqBackend.dynamics) {
      await _ch.invokeMethod<void>(
          'dpGains', {'gains': p.gains, 'preamp': preampFor(p), 'profile': p.name});
      return;
    }
    if (backend == EqBackend.system && info != null) {
      await _ch.invokeMethod<void>('setLevels', {'levels': _levels(p), 'profile': p.name});
    }
  }

  /// Saves "[p] is the profile for output [o]" in the native table (it switches by itself when the output changes).
  Future<void> assign(OutputRef o, EqProfile p) => _ch.invokeMethod<void>('outAssign', {
        'key': o.key,
        'type': o.type,
        'name': o.name,
        'profile': p.name,
        'gains': p.gains,
        'preamp': preampFor(p),
        'levels': _levels(p),
      });

  /// Re-sends every saved assignment with the current contents of its profile (the native table keeps a copy),
  /// and drops the ones whose profile no longer exists. Needs a running back end: the levels depend on it.
  Future<void> resync(List<Assignment> list, List<EqProfile> all) async {
    for (final a in list) {
      EqProfile? p;
      for (final e in all) {
        if (e.name == a.profile) p = e;
      }
      if (p == null) {
        await EngineApi.unassign(a.key);
      } else {
        await assign((key: a.key, type: a.type, name: a.name), p);
      }
    }
  }

  Future<bool> setEnabled(bool on) async =>
      (await _ch.invokeMethod<bool>('setEnabled', {'on': on})) ?? false;

  Future<void> stop() async {
    backend = null;
    info = null;
    await _ch.invokeMethod<void>('stop');
  }
}

/// Result of trying to create one built-in effect (bass boost, virtualizer, loudness).
class FxStatus {
  const FxStatus({required this.ok, this.strengthSupported = true, this.error});

  final bool ok;
  final bool strengthSupported;
  final String? error;

  factory FxStatus.fromMap(Map<dynamic, dynamic> m) => FxStatus(
        ok: m['ok'] == true,
        strengthSupported: m['strengthSupported'] != false,
        error: m['error'] as String?,
      );
}

/// Bass boost / virtualizer / loudness enhancer (android.media.audiofx), keys: bass, virt, loud.
class FxEngine {
  static const _ch = MethodChannel('directional/eq');
  static const keys = ['bass', 'virt', 'loud'];

  static Map<String, FxStatus> _parse(Map<dynamic, dynamic>? m) => {
        for (final k in keys) k: FxStatus.fromMap((m?[k] as Map?) ?? const {'ok': false}),
      };

  /// Which effects this phone lists, WITHOUT creating any: creating one takes its control away from other
  /// equalizer apps (only one app controls an effect type), so nothing is created until the user wants it (AU-25).
  Future<Map<String, FxStatus>> probe() async =>
      _parse(await _ch.invokeMethod<Map<dynamic, dynamic>>('fxProbe'));

  /// Creates the effects named in [only] (all of them when null; one that already exists is kept), disabled, and
  /// reports which ones the device accepted.
  Future<Map<String, FxStatus>> start({List<String>? only}) async => _parse(
      await _ch.invokeMethod<Map<dynamic, dynamic>>('fxStart', only == null ? null : {'names': only}));

  /// [value]: strength 0..1000 for bass/virt, gain in millibels 0..1500 for loud.
  Future<void> set(String name, bool on, int value) => _ch
      .invokeMethod<void>('fxSet', {'name': name, 'on': on, 'value': value});

  Future<void> stop() => _ch.invokeMethod<void>('fxStop');
}

/// A snapshot of the native engine (what is running right now). Also pushed live through an EventChannel.
class EngineStatus {
  const EngineStatus({
    required this.service,
    required this.wanted,
    required this.eqKind,
    required this.eqEnabled,
    required this.eqBands,
    required this.fxActive,
    required this.outputs,
    this.error,
    this.profile = '',
    this.locked = false,
    this.bypass,
    this.output,
    this.assignments = const [],
    this.switchSeq = 0,
    this.switched = false,
  });

  /// The foreground service is running.
  final bool service;

  /// The user asked for the service (it is restarted when the app is opened again).
  final bool wanted;

  /// 'none', 'system' or 'dynamics'.
  final String eqKind;
  final bool eqEnabled;
  final int eqBands;
  final bool fxActive;
  final List<({int type, String name})> outputs;
  final String? error;

  /// Name of the saved profile that was applied last ('' = the native side was never told).
  final String profile;

  /// Manual lock: the profile does not change by itself when the output changes.
  final bool locked;

  /// Why the sound is not being processed although the user wants it: 'create_failed', 'control_lost', or null.
  final String? bypass;

  /// The output the music most likely goes to now (null when none is usable or below Android 6).
  final OutputRef? output;

  /// The saved "output -> profile" table.
  final List<Assignment> assignments;

  /// Grows each time the native side switched profile by itself because the output changed.
  final int switchSeq;

  /// Only in the answer to [EngineApi.outputSync]: that call switched the profile.
  final bool switched;

  static const none = EngineStatus(
    service: false,
    wanted: false,
    eqKind: 'none',
    eqEnabled: false,
    eqBands: 0,
    fxActive: false,
    outputs: [],
  );

  factory EngineStatus.fromMap(Map<dynamic, dynamic> m) {
    final out = m['output'];
    return EngineStatus(
      service: m['service'] == true,
      wanted: m['wanted'] == true,
      eqKind: '${m['eqKind'] ?? 'none'}',
      eqEnabled: m['eqEnabled'] == true,
      eqBands: (m['eqBands'] as num?)?.toInt() ?? 0,
      fxActive: m['fxActive'] == true,
      outputs: [
        for (final o in (m['outputs'] as List?) ?? const [])
          (type: ((o as Map)['type'] as num).toInt(), name: '${o['name'] ?? ''}'),
      ],
      error: m['error'] as String?,
      profile: '${m['profile'] ?? ''}',
      locked: m['locked'] == true,
      bypass: m['bypass'] as String?,
      output: out is Map
          ? (
              key: '${out['key'] ?? ''}',
              type: ((out['type'] as num?) ?? 0).toInt(),
              name: '${out['name'] ?? ''}',
            )
          : null,
      assignments: [
        for (final a in (m['assignments'] as List?) ?? const [])
          if (a is Map)
            (
              key: '${a['key'] ?? ''}',
              type: ((a['type'] as num?) ?? 0).toInt(),
              name: '${a['name'] ?? ''}',
              profile: '${a['profile'] ?? ''}',
            ),
      ],
      switchSeq: (m['switchSeq'] as num?)?.toInt() ?? 0,
      switched: m['switched'] == true,
    );
  }
}

/// Foreground service, permissions, battery settings and live status.
class EngineApi {
  static const _ch = MethodChannel('directional/eq');
  static const _events = EventChannel('directional/status');

  static Future<EngineStatus> status() async {
    try {
      final m = await _ch.invokeMethod<Map<dynamic, dynamic>>('status');
      return m == null ? EngineStatus.none : EngineStatus.fromMap(m);
    } on MissingPluginException {
      return EngineStatus.none;
    }
  }

  /// Emits a new snapshot whenever something changes (route change, effect toggled, service started...).
  static Stream<EngineStatus> stream() => _events
      .receiveBroadcastStream()
      .where((e) => e is Map)
      .map((e) => EngineStatus.fromMap(e as Map));

  static Future<void> svcStart() => _ch.invokeMethod<void>('svcStart', {
        'title': L10n.t('notif_title'),
        'text': L10n.t('notif_text'),
        'stop': L10n.t('notif_stop'),
        'bypass': L10n.t('notif_bypass'),
      });

  static Future<void> svcStop() => _ch.invokeMethod<void>('svcStop');

  /// Right after the equalizer was started: lets the native side pick the profile assigned to the current output
  /// (when the output changed since last time and nothing is locked). [EngineStatus.switched] says whether it did.
  static Future<EngineStatus> outputSync() async {
    final m = await _ch.invokeMethod<Map<dynamic, dynamic>>('outSync');
    return m == null ? EngineStatus.none : EngineStatus.fromMap(m);
  }

  static Future<void> unassign(String key) => _ch.invokeMethod<void>('outUnassign', {'key': key});

  static Future<void> setLock(bool on) => _ch.invokeMethod<void>('lockSet', {'on': on});

  /// Starts the return rule over: rebuild the effects now and, if that fails, keep retrying by itself.
  static Future<void> retry({String reason = 'manual'}) =>
      _ch.invokeMethod<void>('retry', {'reason': reason});

  /// When the app comes back to the screen while the sound is bypassed, try once more.
  static Future<void> retryIfBypassed() async {
    try {
      if ((await status()).bypass != null) await retry(reason: 'app resume');
    } catch (_) {}
  }

  /// The engine's event log: [header] says which phone/Android, [text] is the rolling list of events
  /// (oldest first). Empty when the native side is not there (tests, desktop).
  static Future<({String header, String text})> eventLog() async {
    try {
      final m = await _ch.invokeMethod<Map<dynamic, dynamic>>('logGet');
      return (header: '${m?['header'] ?? ''}', text: '${m?['text'] ?? ''}');
    } on MissingPluginException {
      return (header: '', text: '');
    }
  }

  static Future<void> clearEventLog() async {
    try {
      await _ch.invokeMethod<void>('logClear');
    } on MissingPluginException {}
  }

  /// Adds a line written by the app side (for example "service restarted after the app came back").
  static Future<void> logEvent(String tag, String msg) async {
    try {
      await _ch.invokeMethod<void>('logAdd', {'tag': tag, 'msg': msg});
    } catch (_) {}
  }

  /// 'na' (below Android 13), 'granted' or 'denied'.
  static Future<String> notifStatus() async =>
      (await _ch.invokeMethod<String>('notifStatus')) ?? 'na';

  static Future<String> notifRequest() async =>
      (await _ch.invokeMethod<String>('notifRequest')) ?? 'na';

  static Future<bool> batteryIgnored() async =>
      (await _ch.invokeMethod<bool>('batteryIgnored')) ?? true;

  static Future<void> batteryRequest() => _ch.invokeMethod<void>('batteryRequest');

  /// After the app process was killed: if the user had the service on, bring it back (the app is in front now,
  /// so Android allows it).
  static Future<void> resumeIfWanted() async {
    try {
      final s = await status();
      if (s.wanted && !s.service) {
        await logEvent('app', 'service was wanted but not running: restarting it');
        await svcStart();
      }
    } catch (_) {}
  }
}

/// Plays a short stereo test tone on one channel or both.
class ToneEngine {
  static const _ch = MethodChannel('directional/eq');

  /// [channel]: 'left', 'right' or 'both'.
  Future<void> play(String channel, double freq, double seconds) =>
      _ch.invokeMethod<void>(
          'tone', {'channel': channel, 'freq': freq, 'seconds': seconds});

  Future<void> stop() => _ch.invokeMethod<void>('toneStop');
}
