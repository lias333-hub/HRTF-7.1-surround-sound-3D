import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'device_info_screen.dart';
import 'engine.dart';
import 'engine_screen.dart';
import 'strings.dart';

/// Diagnostics: device info and a left/right channel test (to check for leakage by ear).
class ToolsScreen extends StatefulWidget {
  const ToolsScreen({super.key, required this.lang});

  /// Only here so the screen rebuilds when the language changes.
  final String lang;

  @override
  State<ToolsScreen> createState() => _ToolsScreenState();
}

class _ToolsScreenState extends State<ToolsScreen> {
  static const _toneSeconds = 2.0;

  final _tone = ToneEngine();
  double _freq = 1000;
  String? _playing;
  String? _error;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _tone.stop().catchError((_) {});
    super.dispose();
  }

  String _msg(Object e) => e is PlatformException ? (e.message ?? e.code) : '$e';

  Future<void> _play(String channel) async {
    _timer?.cancel();
    setState(() {
      _playing = channel;
      _error = null;
    });
    try {
      await _tone.play(channel, _freq, _toneSeconds);
    } catch (e) {
      if (mounted) {
        setState(() {
          _playing = null;
          _error = _msg(e);
        });
      }
      return;
    }
    _timer = Timer(
      Duration(milliseconds: (_toneSeconds * 1000).round() + 300),
      () {
        if (mounted) setState(() => _playing = null);
      },
    );
  }

  Widget _channelButton(String channel, String label) {
    final active = _playing == channel;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: active
            ? FilledButton(onPressed: () => _play(channel), child: Text(label))
            : FilledButton.tonal(onPressed: () => _play(channel), child: Text(label)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.t;
    final small = Theme.of(context).textTheme.bodySmall;
    return Scaffold(
      appBar: AppBar(title: Text(t('tools_title'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(t('tool_info')),
              subtitle: Text(t('tool_info_sub')),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const DeviceInfoScreen()),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.settings_input_component),
              title: Text(t('tool_engine')),
              subtitle: Text(t('tool_engine_sub')),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const EngineScreen()),
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.headphones),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(t('tool_test'),
                            style: Theme.of(context).textTheme.titleMedium),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(t('tool_test_sub'), style: small),
                  const SizedBox(height: 12),
                  Text(t('test_freq'), style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 4),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: SegmentedButton<double>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: 250, label: Text('250 Hz')),
                        ButtonSegment(value: 1000, label: Text('1 kHz')),
                        ButtonSegment(value: 4000, label: Text('4 kHz')),
                      ],
                      selected: {_freq},
                      onSelectionChanged: (s) => setState(() => _freq = s.first),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Left is always the physical left, whatever the language direction.
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Row(
                      children: [
                        _channelButton('left', t('test_left')),
                        _channelButton('both', t('test_both')),
                        _channelButton('right', t('test_right')),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_playing != null) Text(t('test_playing'), style: small),
                  if (_error != null)
                    Text(
                      L10n.f('test_fail', {'e': _error!}),
                      style: small?.copyWith(color: Theme.of(context).colorScheme.error),
                    ),
                  const SizedBox(height: 4),
                  Text(t('test_hint'), style: small),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
