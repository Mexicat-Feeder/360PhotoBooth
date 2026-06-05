import 'dart:async';

import 'package:flutter/foundation.dart';

import '../backend/backend_client.dart';
import '../ble/booth_controller.dart';
import '../ble/booth_protocol.dart';
import '../camera/camera_service.dart';

enum AppPhase { attract, info, preview, countdown, capture, processing, result }

/// Drives the guest experience: attract -> info -> countdown -> capture(+spin)
/// -> processing -> result. Owns the booth, camera, and backend.
class FlowController extends ChangeNotifier {
  FlowController({
    required this.booth,
    required this.camera,
    required this.backend,
  });

  final BoothController booth;
  final CameraService camera;
  final BackendClient backend;

  AppPhase phase = AppPhase.attract;

  // guest
  String name = '';
  String email = '';

  // capture config
  SpinDir dir = SpinDir.ccw;
  int speed = 5;
  int spinSecs = 8;

  // processing/result
  double progress = 0;
  String? previewUrl;
  String? resultUrl;
  String? error;
  String? _videoPath;

  Future<void> init() async {
    await camera.init();
    // connect the booth in the background so it's ready by capture time
    unawaited(booth.connect());
  }

  void go(AppPhase p) {
    phase = p;
    notifyListeners();
  }

  void setGuest({String? name, String? email}) {
    if (name != null) this.name = name;
    if (email != null) this.email = email;
    notifyListeners();
  }

  void reset() {
    name = '';
    email = '';
    progress = 0;
    previewUrl = null;
    resultUrl = null;
    error = null;
    _videoPath = null;
    phase = AppPhase.attract;
    notifyListeners();
  }

  /// Called when the countdown finishes: record + spin together, then process.
  Future<void> runCaptureAndProcess() async {
    go(AppPhase.capture);
    error = null;

    try {
      await camera.startRecording();
      // spin the real rig (controller auto-stops after spinSecs too)
      await booth.spin(dir, speed, spinSecs);
      await Future<void>.delayed(Duration(seconds: spinSecs));
      await booth.stop();
      _videoPath = await camera.stopRecording();
    } catch (e) {
      error = 'capture failed: $e';
      go(AppPhase.result);
      return;
    }

    go(AppPhase.processing);
    await _process();
  }

  Future<void> _process() async {
    progress = 0;
    try {
      final jobId = await backend.uploadJob(_videoPath!, name, email);
      await for (final p in backend.pollProgress(jobId)) {
        progress = p.progress;
        previewUrl =
            p.previewUrl == null ? null : backend.absolute(p.previewUrl!);
        if (p.failed) {
          error = 'generation failed';
          break;
        }
        if (p.done) {
          resultUrl =
              p.resultUrl == null ? null : backend.absolute(p.resultUrl!);
          break;
        }
        notifyListeners();
      }
    } catch (e) {
      error = 'processing failed: $e';
    }
    go(AppPhase.result);
  }
}
