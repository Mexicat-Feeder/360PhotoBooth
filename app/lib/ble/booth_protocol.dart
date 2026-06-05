import 'dart:typed_data';

/// Spin direction. Confirmed live: cmd byte 0x22 = CCW, 0x11 = CW.
enum SpinDir { cw, ccw }

/// Pure frame builder for the Chacktok / KT6368A 360-booth controller.
///
/// Port of ble/booth.py (verified against two btsnoop captures). Frame:
///   AA CC | cmd  speed  22 00  secs  11 00 | CHK | CC AA
///   cmd   = 0x22 CCW / 0x11 CW / 0x33 stop
///   speed = N*0x11  (N 1..9; >9 clamps to max on the controller)
///   secs  = spin duration in seconds (controller auto-stops)
///   CHK   = sum(bytes[2..8]) & 0xFF
class BoothProtocol {
  static const int cmdCcw = 0x22;
  static const int cmdCw = 0x11;
  static const int cmdStop = 0x33;

  /// fff1 is used for BOTH write (without response) and notify on this unit.
  static const String charFff1 = 'fff1';

  /// Speed setting N -> byte[3], encoded by the app as N*0x11 == (N<<4)|N.
  static int encSpeed(int n) {
    n = n.clamp(1, 9);
    return (n << 4) | n;
  }

  static Uint8List build(int cmd, int speedN, int secs) {
    secs = secs.clamp(0, 255);
    final payload = <int>[
      cmd & 0xFF,
      encSpeed(speedN),
      0x22,
      0x00,
      secs & 0xFF,
      0x11,
      0x00,
    ];
    var chk = 0;
    for (final b in payload) {
      chk += b;
    }
    chk &= 0xFF;
    return Uint8List.fromList([0xAA, 0xCC, ...payload, chk, 0xCC, 0xAA]);
  }

  static Uint8List run(SpinDir dir, int speedN, int secs) =>
      build(dir == SpinDir.cw ? cmdCw : cmdCcw, speedN, secs);

  static Uint8List stop() => build(cmdStop, 2, 0);

  static String hex(Uint8List b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join(' ');
}
