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
