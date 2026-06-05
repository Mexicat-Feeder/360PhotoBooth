import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../theme.dart';

/// Abstraction over video capture so the flow runs on Linux desktop (Fake) and
/// later on Android (real `camera` plugin) unchanged.
abstract class CameraService {
  Future<void> init();

  /// Begin/refresh the live preview (camera screen visible).
  Future<void> startPreview();

  /// Stop the live preview (release the camera when not needed).
  Future<void> stopPreview();

  Future<void> startRecording();

  /// Stops recording and returns the local file path of the captured video.
  Future<String> stopRecording();

  /// A live preview widget.
  Widget buildPreview();

  void dispose();
}

/// Linux/desktop & emulator stand-in: no real camera. Shows an animated
/// placeholder and writes a small dummy file so the upload path is exercised.
class FakeCameraService implements CameraService {
  @override
  Future<void> init() async {}

  @override
  Future<void> startPreview() async {}

  @override
  Future<void> stopPreview() async {}

  @override
  Future<void> startRecording() async {}

  @override
  Future<String> stopRecording() async {
    // Emit a REAL sample clip (Linux dev has no camera) so the backend/ComfyUI
    // gets valid video. On the tablet, RealCameraService records the guest.
    final dir = Directory.systemTemp.createTempSync('booth_capture_');
    final f = File('${dir.path}/capture.mp4');
    final bytes = await rootBundle.load('assets/sample_capture.mp4');
    await f.writeAsBytes(bytes.buffer.asUint8List());
    return f.path;
  }

  @override
  Widget buildPreview() => const _FakePreview();

  @override
  void dispose() {}
}

class _FakePreview extends StatelessWidget {
  const _FakePreview();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Brand.redBright.withValues(alpha: 0.5), width: 2),
      ),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam, size: 64, color: Colors.white24),
            SizedBox(height: 12),
            Text('camera preview\n(real on tablet)',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38)),
          ],
        ),
      ),
    );
  }
}
