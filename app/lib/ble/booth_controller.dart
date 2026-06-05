import 'booth_protocol.dart';

enum BoothState { disconnected, scanning, connecting, connected, error }

/// Abstraction over the booth's BLE control so the UI doesn't care whether it's
/// talking to the real rig (universal_ble) or a fake (emulator / UI dev).
abstract class BoothController {
  BoothState get state;
  Stream<BoothState> get stateStream;

  /// Human-readable activity log (commands sent, acks, connection events).
  Stream<String> get log;

  /// Scan for the controller by name and connect (with retries).
  Future<void> connect();
  Future<void> disconnect();

  /// Spin [dir] at [speed] (1..9) for [secs] seconds (controller auto-stops).
  Future<void> spin(SpinDir dir, int speed, int secs);
  Future<void> stop();

  void dispose();
}
