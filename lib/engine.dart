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

/// Equalizer bridge. Two interchangeable back ends sit behind it:
/// the system [EqBackend.system] equalizer (few bands, works on old Android) and
/// [EqBackend.dynamics] (one real band per UI band plus a limiter, Android 9+).
class EqEngine {
  static const _ch = MethodChannel('directional/eq');

  /// The system equalizer's real bands (only set while [backend] is [EqBackend.system]).
  DeviceInfo? info;
  EqBackend? backend;

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

  /// Sends the profile to whichever back end is running.
  Future<void> apply(EqProfile p) async {
    if (backend == EqBackend.dynamics) {
      await _ch.invokeMethod<void>('dpGains', {'gains': p.gains, 'preamp': p.preamp});
      return;
    }
    final i = info;
    if (backend == EqBackend.system && i != null) {
      final levels = deviceLevels(
        gains: p.gains,
        preamp: p.preamp,
        lows: i.lows,
        highs: i.highs,
        centers: i.centers,
        minMb: i.minMb,
        maxMb: i.maxMb,
      );
      await _ch.invokeMethod<void>('setLevels', {'levels': levels});
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

  /// Creates the effects (disabled) and reports which ones the device accepted.
  Future<Map<String, FxStatus>> start() async {
    final m = await _ch.invokeMethod<Map<dynamic, dynamic>>('fxStart');
    return {
      for (final k in keys)
        k: FxStatus.fromMap((m?[k] as Map?) ?? const {'ok': false}),
    };
  }

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

  static const none = EngineStatus(
    service: false,
    wanted: false,
    eqKind: 'none',
    eqEnabled: false,
    eqBands: 0,
    fxActive: false,
    outputs: [],
  );

  factory EngineStatus.fromMap(Map<dynamic, dynamic> m) => EngineStatus(
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
      );
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
      });

  static Future<void> svcStop() => _ch.invokeMethod<void>('svcStop');

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
      if (s.wanted && !s.service) await svcStart();
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
