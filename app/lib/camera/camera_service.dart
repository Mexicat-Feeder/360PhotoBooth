import 'dart:io';

import 'package:flutter/material.dart';

import '../theme.dart';

/// Abstraction over video capture so the flow runs on Linux desktop (Fake) and
/// later on Android (real `camera` plugin) unchanged.
abstract class CameraService {
  Future<void> init();
  Future<void> startRecording();

  /// Stops recording and returns the local file path of the captured video.
  Future<String> stopRecording();

  /// A preview widget for the capture screen.
  Widget buildPreview();

  void dispose();
}

/// Linux/desktop & emulator stand-in: no real camera. Shows an animated
/// placeholder and writes a small dummy file so the upload path is exercised.
class FakeCameraService implements CameraService {
  @override
  Future<void> init() async {}

  @override
  Future<void> startRecording() async {}

  @override
  Future<String> stopRecording() async {
    final dir = Directory.systemTemp.createTempSync('booth_capture_');
    final f = File('${dir.path}/capture.mp4');
    // dummy payload — enough to exercise multipart upload to the mock backend
    await f.writeAsBytes(List<int>.filled(64 * 1024, 0));
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
