import 'dart:async';
import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

import 'booth_controller.dart';
import 'booth_protocol.dart';

/// Real BLE control via universal_ble (Linux desktop + Android + iOS).
/// Direct port of ble/booth.py, hardened for the flaky KT6368A module:
///  - checks already-connected system devices before scanning
///  - treats an OS-level connection as success even if connect() throws/times out
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

  bool _matches(BleDevice d) => (d.name ?? '').contains(_namePrefix);

  @override
  Future<void> connect() async {
    if (_state == BoothState.connected) return;
    _setState(BoothState.scanning);

    final device = await _findDevice();
    if (device == null) {
      _setState(BoothState.disconnected);
      _log('controller not found (powered + disconnected from the Chacktok app '
          '+ in range?)');
      return;
    }
    _device = device;

    // Connect with retries. bluez's Connect() is slow on this module and keeps
    // running after universal_ble's Dart future times out — so we (a) use a
    // generous timeout, (b) poll isConnected for a few seconds after each
    // attempt (it often completes late), and (c) disconnect to clear the
    // "operation already in progress" state before retrying.
    _setState(BoothState.connecting);
    final connected = await _tryConnect(device);
    if (!connected) {
      _setState(BoothState.disconnected);
      _log('could not connect');
      return;
    }
    _log('connected; discovering services...');

    // Discover services and locate the fff1 command characteristic (retry once).
    for (var attempt = 1; attempt <= 2 && _cmd == null; attempt++) {
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
        _log('discoverServices attempt $attempt failed: $e');
      }
      if (_cmd == null) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
      }
    }

    if (_cmd == null) {
      _log('fff1 characteristic not found');
      _setState(BoothState.error);
      return;
    }
    _setState(BoothState.connected);
    _log('ready (cmd char ${_cmd!.uuid})');
  }

  Future<bool> _tryConnect(BleDevice device) async {
    for (var i = 1; i <= 4; i++) {
      if (await device.isConnected) return true;
      if (i > 1) {
        // clear any half-open / in-progress bluez state before retrying
        try {
          await device.disconnect();
        } catch (_) {}
        await Future<void>.delayed(const Duration(milliseconds: 1500));
      }
      _log('connect attempt $i...');
      // bluez often reports connected BEFORE its connect() future resolves
      // (the future may hang until timeout), so fire connect and poll
      // isConnected concurrently — proceed the instant the link is up.
      unawaited(device
          .connect(timeout: const Duration(seconds: 25))
          .catchError((Object e) => _log('  attempt $i: $e')));
      for (var j = 0; j < 50; j++) {
        if (await device.isConnected) {
          _log('  connected');
          return true;
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
    return false;
  }

  /// Prefer an already-known/connected OS device (it won't be advertising if
  /// connected), otherwise scan.
  Future<BleDevice?> _findDevice() async {
    try {
      final sys = await UniversalBle.getSystemDevices();
      for (final d in sys) {
        if (_matches(d)) {
          _log('found via system devices: "${d.name}" (${d.deviceId})');
          return d;
        }
      }
    } catch (_) {
      // not supported / nothing connected — fall through to scanning
    }

    _log('scanning for "$_namePrefix"...');
    final found = Completer<BleDevice>();
    _scanSub = UniversalBle.scanStream.listen((d) {
      if (_matches(d) && !found.isCompleted) {
        _log('found "${d.name}" (${d.deviceId})');
        found.complete(d);
      }
    });
    try {
      await UniversalBle.startScan();
    } catch (e) {
      _log('startScan failed: $e');
    }
    try {
      return await found.future.timeout(const Duration(seconds: 20));
    } on TimeoutException {
      return null;
    } finally {
      await _stopScan();
    }
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
