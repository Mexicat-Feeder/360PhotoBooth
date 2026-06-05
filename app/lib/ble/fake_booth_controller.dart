import 'dart:async';

import 'booth_controller.dart';
import 'booth_protocol.dart';

/// Simulated booth — for the Android emulator / pure-UI work where there's no
/// Bluetooth radio. Logs the exact frames it "would" send.
class FakeBoothController implements BoothController {
  final _stateCtrl = StreamController<BoothState>.broadcast();
  final _logCtrl = StreamController<String>.broadcast();
  BoothState _state = BoothState.disconnected;
  Timer? _autoStop;

  @override
  BoothState get state => _state;
  @override
  Stream<BoothState> get stateStream => _stateCtrl.stream;
  @override
  Stream<String> get log => _logCtrl.stream;

  void _set(BoothState s) {
    _state = s;
    _stateCtrl.add(s);
  }

  @override
  Future<void> connect() async {
    _set(BoothState.scanning);
    _logCtrl.add('[fake] scanning...');
    await Future<void>.delayed(const Duration(milliseconds: 600));
    _set(BoothState.connecting);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    _set(BoothState.connected);
    _logCtrl.add('[fake] connected');
  }

  @override
  Future<void> spin(SpinDir dir, int speed, int secs) async {
    final f = BoothProtocol.run(dir, speed, secs);
    _logCtrl.add('[fake] spin ${dir.name} speed=$speed secs=$secs '
        '-> ${BoothProtocol.hex(f)}');
    _autoStop?.cancel();
    _autoStop = Timer(Duration(seconds: secs), () => _logCtrl.add('[fake] auto-stopped'));
  }

  @override
  Future<void> stop() async {
    _autoStop?.cancel();
    _logCtrl.add('[fake] stop -> ${BoothProtocol.hex(BoothProtocol.stop())}');
  }

  @override
  Future<void> disconnect() async {
    _autoStop?.cancel();
    _set(BoothState.disconnected);
    _logCtrl.add('[fake] disconnected');
  }

  @override
  void dispose() {
    _autoStop?.cancel();
    _stateCtrl.close();
    _logCtrl.close();
  }
}
