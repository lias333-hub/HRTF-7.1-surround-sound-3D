import 'package:flutter/services.dart';

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

/// Thin wrapper over the native android.media.audiofx.Equalizer bridge.
class EqEngine {
  static const _ch = MethodChannel('directional/eq');

  DeviceInfo? info;

  Future<DeviceInfo> start({int session = 0}) async {
    final m = await _ch
        .invokeMethod<Map<dynamic, dynamic>>('start', {'session': session});
    info = DeviceInfo.fromMap(m!);
    return info!;
  }

  Future<void> setLevels(List<int> levels) =>
      _ch.invokeMethod<void>('setLevels', {'levels': levels});

  Future<bool> setEnabled(bool on) async =>
      (await _ch.invokeMethod<bool>('setEnabled', {'on': on})) ?? false;

  Future<void> stop() => _ch.invokeMethod<void>('stop');
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

/// Plays a short stereo test tone on one channel or both.
class ToneEngine {
  static const _ch = MethodChannel('directional/eq');

  /// [channel]: 'left', 'right' or 'both'.
  Future<void> play(String channel, double freq, double seconds) =>
      _ch.invokeMethod<void>(
          'tone', {'channel': channel, 'freq': freq, 'seconds': seconds});

  Future<void> stop() => _ch.invokeMethod<void>('toneStop');
}
