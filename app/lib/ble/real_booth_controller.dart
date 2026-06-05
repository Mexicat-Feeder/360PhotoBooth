import 'dart:async';
import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

import 'booth_controller.dart';
import 'booth_protocol.dart';

/// Real BLE control via universal_ble (works on Linux desktop + Android + iOS).
/// Direct port of ble/booth.py.
class RealBoothController implements BoothController {
  static const String _namePrefix = '360 Controller';

  final _stateCtrl = StreamController<BoothState>.broadcast();
  final _logCtrl = StreamController<String>.broadcast();

  BoothState _state = BoothState.disconnected;
  BleDevice? _device;
  BleCharacteristic? _cmd; // fff1
  StreamSubscription<BleDevice>? _scanSub;

  @override
  BoothState get state => _state;
  @override
  Stream<BoothState> get stateStream => _stateCtrl.stream;
  @override
  Stream<String> get log => _logCtrl.stream;

  void _setState(BoothState s) {
    _state = s;
    if (!_stateCtrl.isClosed) _stateCtrl.add(s);
  }

  void _log(String m) {
    if (!_logCtrl.isClosed) _logCtrl.add(m);
  }

  @override
  Future<void> connect() async {
    if (_state == BoothState.connected) return;
    _setState(BoothState.scanning);
    _log('scanning for "$_namePrefix"...');

    final found = Completer<BleDevice>();
    _scanSub = UniversalBle.scanStream.listen((d) {
      final name = d.name ?? '';
      if (name.contains(_namePrefix) && !found.isCompleted) {
        _log('found "$name" (${d.deviceId})');
        found.complete(d);
      }
    });

    try {
      await UniversalBle.startScan();
    } catch (e) {
      _log('startScan failed: $e');
    }

    BleDevice device;
    try {
      device = await found.future.timeout(const Duration(seconds: 20));
    } on TimeoutException {
      await _stopScan();
      _setState(BoothState.disconnected);
      _log('controller not found (powered + disconnected from the Chacktok app '
          '+ in range?)');
      return;
    }
    await _stopScan();
    _device = device;

    // Connect with retries — the cheap KT6368A module is flaky.
    _setState(BoothState.connecting);
    var connected = false;
    for (var i = 1; i <= 6; i++) {
      try {
        _log('connect attempt $i...');
        await device.connect(timeout: const Duration(seconds: 20));
        connected = true;
        break;
      } catch (_) {
        _log('  attempt $i failed; retrying...');
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
    if (!connected) {
      _setState(BoothState.disconnected);
      _log('could not connect after 6 tries');
      return;
    }

    // Discover services and locate the fff1 command characteristic.
    try {
      final services = await device.discoverServices();
      for (final s in services) {
        for (final ch in s.characteristics) {
          if (ch.uuid.toLowerCase().contains(BoothProtocol.charFff1)) {
            _cmd = ch;
          }
        }
      }
    } catch (e) {
      _log('discoverServices failed: $e');
    }

    if (_cmd == null) {
      _log('fff1 characteristic not found');
      _setState(BoothState.error);
      return;
    }
    _setState(BoothState.connected);
    _log('connected; ready (cmd char ${_cmd!.uuid})');
  }

  Future<void> _stopScan() async {
    try {
      await UniversalBle.stopScan();
    } catch (_) {}
    await _scanSub?.cancel();
    _scanSub = null;
  }

  Future<void> _write(Uint8List frame) async {
    final ch = _cmd;
    if (ch == null) {
      _log('not connected');
      return;
    }
    _log('-> ${BoothProtocol.hex(frame)}');
    try {
      await ch.write(frame, withResponse: false);
    } catch (e) {
      _log('write failed: $e');
    }
  }

  @override
  Future<void> spin(SpinDir dir, int speed, int secs) =>
      _write(BoothProtocol.run(dir, speed, secs));

  @override
  Future<void> stop() => _write(BoothProtocol.stop());

  @override
  Future<void> disconnect() async {
    await _stopScan();
    try {
      await stop();
    } catch (_) {}
    try {
      await _device?.disconnect();
    } catch (_) {}
    _cmd = null;
    _device = null;
    _setState(BoothState.disconnected);
    _log('disconnected');
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _stateCtrl.close();
    _logCtrl.close();
  }
}
