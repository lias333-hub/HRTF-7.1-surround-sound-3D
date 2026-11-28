import 'package:flutter/services.dart';

import 'engine.dart';

// Effect type UUIDs as reported by AudioEffect.queryEffects() (lower case).
const kFxEqualizer = '0bed4300-ddd6-11db-8f34-0002a5d5c51b';
const kFxBassBoost = '0634f220-ddd4-11db-a0fc-0002a5d5c51b';
// Checked against the Android 14 emulator's dumpsys (the "..8bc1.." variant I first wrote from memory was wrong).
const kFxVirtualizer = '37cc2c00-dddd-11db-8577-0002a5d5c51b';
const kFxLoudness = 'fe3199be-aed0-413f-87bb-11260eb63cf1';

class EffectEntry {
  const EffectEntry({
    required this.name,
    required this.implementor,
    required this.type,
    required this.uuid,
  });

  final String name;
  final String implementor;
  final String type;
  final String uuid;
}

class OutputEntry {
  const OutputEntry(this.type, this.name);

  final int type;
  final String name;

  /// AudioDeviceInfo type constants, only the ones that matter for headphones.
  String get typeName {
    switch (type) {
      case 1:
        return 'Earpiece';
      case 2:
        return 'Speaker';
      case 3:
        return 'Wired headset';
      case 4:
        return 'Wired headphones';
      case 7:
        return 'Bluetooth SCO';
      case 8:
        return 'Bluetooth A2DP';
      case 9:
        return 'HDMI';
      case 11:
        return 'USB device';
      case 22:
        return 'USB headset';
      case 18:
        return 'Telephony';
      case 26:
        return 'Bluetooth LE headset';
      case 27:
        return 'Bluetooth LE speaker';
      default:
        return 'Type $type';
    }
  }

  @override
  String toString() => name.isEmpty ? typeName : '$typeName ($name)';
}

/// [consent]: works once the user agrees (the app already has it). [consentPlanned]: the phone would allow it with
/// the user's consent, but the app has not built it yet (AU-24: a capability of the system must not read like a
/// feature of the app).
enum CapState { yes, consent, consentPlanned, no, needs, planned }

class Capability {
  const Capability(this.key, this.state, [this.version]);

  /// Used to build the string key 'cap_<key>'.
  final String key;
  final CapState state;

  /// For [CapState.needs]: the Android version number required.
  final int? version;
}

/// What this phone reports about its audio stack. Parsed from the native 'deviceInfo' call.
class DeviceReport {
  const DeviceReport({
    required this.manufacturer,
    required this.model,
    required this.release,
    required this.sdk,
    required this.abis,
    required this.sampleRate,
    required this.framesPerBuffer,
    required this.outputs,
    required this.effects,
    required this.eq,
    required this.eqError,
    this.dynOk,
    this.dynError,
  });

  final String manufacturer;
  final String model;
  final String release;
  final int sdk;
  final List<String> abis;
  final int? sampleRate;
  final int? framesPerBuffer;
  final List<OutputEntry> outputs;
  final List<EffectEntry> effects;
  final DeviceInfo? eq;
  final String? eqError;

  /// Whether a Dynamics Processing effect could be created on the global mix (null = not reported).
  /// Creating one does not prove it is audible: that is checked by ear.
  final bool? dynOk;
  final String? dynError;

  static const _ch = MethodChannel('directional/eq');

  static Future<DeviceReport> load() async {
    final m = await _ch.invokeMethod<Map<dynamic, dynamic>>('deviceInfo');
    return DeviceReport.fromMap(m!);
  }

  factory DeviceReport.fromMap(Map<dynamic, dynamic> m) {
    List<T> list<T>(String k, T Function(dynamic) f) =>
        ((m[k] as List?) ?? const []).map(f).toList();
    final eqRaw = m['eq'];
    final dynRaw = m['dynamics'];
    return DeviceReport(
      manufacturer: '${m['manufacturer'] ?? ''}',
      model: '${m['model'] ?? ''}',
      release: '${m['release'] ?? ''}',
      sdk: (m['sdk'] as num?)?.toInt() ?? 0,
      abis: list<String>('abis', (e) => '$e'),
      sampleRate: int.tryParse('${m['sampleRate'] ?? ''}'),
      framesPerBuffer: int.tryParse('${m['framesPerBuffer'] ?? ''}'),
      outputs: list<OutputEntry>(
        'outputs',
        (e) => OutputEntry((e['type'] as num).toInt(), '${e['name'] ?? ''}'),
      ),
      effects: list<EffectEntry>(
        'effects',
        (e) => EffectEntry(
          name: '${e['name'] ?? ''}',
          implementor: '${e['implementor'] ?? ''}',
          type: '${e['type'] ?? ''}',
          uuid: '${e['uuid'] ?? ''}',
        ),
      ),
      eq: eqRaw is Map ? DeviceInfo.fromMap(eqRaw) : null,
      eqError: m['eqError'] as String?,
      dynOk: dynRaw is Map ? dynRaw['ok'] == true : null,
      dynError: dynRaw is Map ? dynRaw['error'] as String? : null,
    );
  }

  String get phone => model.toLowerCase().startsWith(manufacturer.toLowerCase())
      ? model
      : '$manufacturer $model'.trim();

  String get androidName => '$release (API $sdk)';

  bool hasEffect(String typeUuid) =>
      effects.any((e) => e.type.toLowerCase() == typeUuid);

  /// An honest list of what is and is not possible on this phone.
  List<Capability> capabilities() => [
        Capability('eq', eq != null ? CapState.yes : CapState.no),
        Capability('bass', hasEffect(kFxBassBoost) ? CapState.yes : CapState.no),
        Capability('virt', hasEffect(kFxVirtualizer) ? CapState.yes : CapState.no),
        Capability('loud', hasEffect(kFxLoudness) ? CapState.yes : CapState.no),
        sdk < 28
            ? const Capability('dyn', CapState.needs, 9)
            : Capability('dyn', dynOk == false ? CapState.no : CapState.yes),
        sdk >= 29
            ? const Capability('capture', CapState.consentPlanned)
            : const Capability('capture', CapState.needs, 10),
        const Capability('player', CapState.planned),
      ];

  /// Plain-English report for sharing (always English, so it is easy to compare between phones).
  String toText() {
    final b = StringBuffer()
      ..writeln('Directional Audio device report')
      ..writeln('Phone: $phone')
      ..writeln('Android: $androidName')
      ..writeln('ABI: ${abis.join(', ')}')
      ..writeln('Output sample rate: ${sampleRate ?? '?'} Hz, '
          'buffer: ${framesPerBuffer ?? '?'} frames')
      ..writeln('Outputs: ${outputs.isEmpty ? 'none' : outputs.join('; ')}');
    final e = eq;
    if (e != null) {
      b.writeln(
          'Equalizer: ${e.bands} bands, range ±${(e.maxMb / 100).toStringAsFixed(0)} dB');
      for (var i = 0; i < e.bands; i++) {
        b.writeln('  Band $i: ${e.lows[i].round()}-${e.highs[i].round()} Hz '
            '(center ${e.centers[i].round()})');
      }
    } else {
      b.writeln('Equalizer: unavailable${eqError == null ? '' : ' ($eqError)'}');
    }
    if (dynOk != null) {
      b.writeln('Dynamics Processing: ${dynOk! ? 'can be created' : 'failed'}'
          '${dynError == null ? '' : ' ($dynError)'}');
    }
    b.writeln('Effects (${effects.length}):');
    for (final f in effects) {
      b.writeln('  ${f.name} / ${f.implementor} [type ${f.type}]');
    }
    b.writeln('Capabilities:');
    for (final c in capabilities()) {
      final s = switch (c.state) {
        CapState.yes => 'available',
        CapState.consent => 'possible with user consent',
        CapState.consentPlanned => 'possible with user consent (not built into the app yet)',
        CapState.no => 'not available',
        CapState.needs => 'needs Android ${c.version}+',
        CapState.planned => 'planned',
      };
      b.writeln('  ${c.key}: $s');
    }
    return b.toString();
  }
}
