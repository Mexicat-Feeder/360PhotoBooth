// Frame-builder tests — the Dart equivalent of `ble/booth.py --selftest`.
// Verifies BoothProtocol reproduces frames captured from the real Chacktok app.
import 'package:flutter_test/flutter_test.dart';
import 'package:booth360/ble/booth_protocol.dart';

String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join(' ');

void main() {
  // (cmd, speedN, secs) -> expected frame, straight from the btsnoop captures.
  final vectors = <(int, int, int), String>{
    (BoothProtocol.cmdCcw, 1, 5): 'aa cc 22 11 22 00 05 11 00 6b cc aa',
    (BoothProtocol.cmdCcw, 2, 10): 'aa cc 22 22 22 00 0a 11 00 81 cc aa',
    (BoothProtocol.cmdCw, 1, 5): 'aa cc 11 11 22 00 05 11 00 5a cc aa',
    (BoothProtocol.cmdCw, 5, 5): 'aa cc 11 55 22 00 05 11 00 9e cc aa',
    (BoothProtocol.cmdCw, 5, 10): 'aa cc 11 55 22 00 0a 11 00 a3 cc aa',
    (BoothProtocol.cmdStop, 1, 0): 'aa cc 33 11 22 00 00 11 00 77 cc aa',
    (BoothProtocol.cmdStop, 5, 0): 'aa cc 33 55 22 00 00 11 00 bb cc aa',
  };

  test('frame builder matches captured frames', () {
    vectors.forEach((k, expected) {
      final (cmd, speed, secs) = k;
      expect(_hex(BoothProtocol.build(cmd, speed, secs)), expected,
          reason: 'cmd=$cmd speed=$speed secs=$secs');
    });
  });

  test('speed clamps to 1..9', () {
    expect(BoothProtocol.encSpeed(0), 0x11);
    expect(BoothProtocol.encSpeed(5), 0x55);
    expect(BoothProtocol.encSpeed(99), 0x99);
  });

  test('run() picks the right direction byte', () {
    expect(BoothProtocol.run(SpinDir.ccw, 1, 5)[2], BoothProtocol.cmdCcw);
    expect(BoothProtocol.run(SpinDir.cw, 1, 5)[2], BoothProtocol.cmdCw);
  });
}
