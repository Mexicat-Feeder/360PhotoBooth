import 'package:flutter/material.dart';

import '../ble/booth_controller.dart';
import '../ble/booth_protocol.dart';

/// "booth.py, in the app" — connect, then drive direction / speed / duration to
/// validate real BLE control of the rig from the Flutter build.
class BoothTestScreen extends StatefulWidget {
  const BoothTestScreen({super.key, required this.controller});

  final BoothController controller;

  @override
  State<BoothTestScreen> createState() => _BoothTestScreenState();
}

class _BoothTestScreenState extends State<BoothTestScreen> {
  BoothState _state = BoothState.disconnected;
  final List<String> _log = [];
  final ScrollController _scroll = ScrollController();

  SpinDir _dir = SpinDir.ccw;
  double _speed = 5;
  double _secs = 8;

  @override
  void initState() {
    super.initState();
    widget.controller.stateStream.listen((s) => setState(() => _state = s));
    widget.controller.log.listen((m) {
      setState(() {
        _log.add(m);
        if (_log.length > 200) _log.removeAt(0);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    });
  }

  Color get _stateColor => switch (_state) {
        BoothState.connected => Colors.green,
        BoothState.scanning || BoothState.connecting => Colors.orange,
        BoothState.error => Colors.red,
        BoothState.disconnected => Colors.grey,
      };

  bool get _connected => _state == BoothState.connected;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Booth BLE Test'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(children: [
              Icon(Icons.circle, size: 12, color: _stateColor),
              const SizedBox(width: 6),
              Text(_state.name),
            ]),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _state == BoothState.disconnected ||
                          _state == BoothState.error
                      ? c.connect
                      : null,
                  icon: const Icon(Icons.bluetooth_searching),
                  label: const Text('Connect'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _state == BoothState.disconnected
                      ? null
                      : c.disconnect,
                  icon: const Icon(Icons.bluetooth_disabled),
                  label: const Text('Disconnect'),
                ),
              ),
            ]),
            const SizedBox(height: 20),

            // Direction
            SegmentedButton<SpinDir>(
              segments: const [
                ButtonSegment(
                    value: SpinDir.ccw,
                    label: Text('CCW (0x22)'),
                    icon: Icon(Icons.rotate_left)),
                ButtonSegment(
                    value: SpinDir.cw,
                    label: Text('CW (0x11)'),
                    icon: Icon(Icons.rotate_right)),
              ],
              selected: {_dir},
              onSelectionChanged: (s) => setState(() => _dir = s.first),
            ),
            const SizedBox(height: 16),

            Text('Speed: ${_speed.round()}  (1–9)'),
            Slider(
              value: _speed,
              min: 1,
              max: 9,
              divisions: 8,
              label: _speed.round().toString(),
              onChanged: (v) => setState(() => _speed = v),
            ),

            Text('Duration: ${_secs.round()} s'),
            Slider(
              value: _secs,
              min: 1,
              max: 30,
              divisions: 29,
              label: '${_secs.round()}s',
              onChanged: (v) => setState(() => _secs = v),
            ),
            const SizedBox(height: 8),

            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(vertical: 16)),
                  onPressed: _connected
                      ? () => c.spin(_dir, _speed.round(), _secs.round())
                      : null,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('SPIN'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(vertical: 16)),
                  onPressed: _connected ? c.stop : null,
                  icon: const Icon(Icons.stop),
                  label: const Text('STOP'),
                ),
              ),
            ]),
            const SizedBox(height: 16),

            const Text('Log', style: TextStyle(fontWeight: FontWeight.bold)),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.builder(
                  controller: _scroll,
                  itemCount: _log.length,
                  itemBuilder: (_, i) => Text(
                    _log[i],
                    style: const TextStyle(
                        color: Colors.greenAccent,
                        fontFamily: 'monospace',
                        fontSize: 12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }
}
