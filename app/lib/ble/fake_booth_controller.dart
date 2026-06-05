import 'dart:async';

import 'booth_controller.dart';
import 'booth_protocol.dart';

/// Simulated booth — for the Android emulator / pure-UI work where there's no
/// Bluetooth radio. Logs the exact frames it "would" send.
class FakeBoothController implements BoothController {
  final _stateCtrl = StreamController<BoothState>.broadcast();
  final _logCtrl = StreamController<String>.broadcast();
  final List<String> _history = <String>[];
  BoothState _state = BoothState.disconnected;
  Timer? _autoStop;

  @override
  BoothState get state => _state;
  @override
  Stream<BoothState> get stateStream => _stateCtrl.stream;
  @override
  Stream<String> get log => _logCtrl.stream;
  @override
  List<String> get logHistory => List.unmodifiable(_history);

  void _log(String m) {
    _history.add(m);
    if (_history.length > 400) _history.removeAt(0);
    _logCtrl.add(m);
  }

  void _set(BoothState s) {
    _state = s;
    _stateCtrl.add(s);
  }

  @override
  Future<void> connect() async {
    _set(BoothState.scanning);
    _log('[fake] scanning...');
    await Future<void>.delayed(const Duration(milliseconds: 600));
    _set(BoothState.connecting);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    _set(BoothState.connected);
    _log('[fake] connected');
  }

  @override
  Future<void> spin(SpinDir dir, int speed, int secs) async {
    final f = BoothProtocol.run(dir, speed, secs);
    _log('[fake] spin ${dir.name} speed=$speed secs=$secs '
        '-> ${BoothProtocol.hex(f)}');
    _autoStop?.cancel();
    _autoStop = Timer(Duration(seconds: secs), () => _log('[fake] auto-stopped'));
  }

  @override
  Future<void> stop() async {
    _autoStop?.cancel();
    _log('[fake] stop -> ${BoothProtocol.hex(BoothProtocol.stop())}');
  }

  @override
  Future<void> disconnect() async {
    _autoStop?.cancel();
    _set(BoothState.disconnected);
    _log('[fake] disconnected');
  }

  @override
  void dispose() {
    _autoStop?.cancel();
    _stateCtrl.close();
    _logCtrl.close();
  }
}
