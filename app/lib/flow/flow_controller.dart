import 'dart:async';

import 'package:flutter/foundation.dart';

import '../backend/backend_client.dart';
import '../ble/booth_controller.dart';
import '../ble/booth_protocol.dart';
import '../camera/camera_service.dart';

enum AppPhase {
  attract,
  info,
  style,
  preview,
  countdown,
  capture,
  processing,
  result
}

/// Drives the guest experience: attract -> info -> countdown -> capture(+spin)
/// -> processing -> result. Owns the booth, camera, and backend.
class FlowController extends ChangeNotifier {
  FlowController({
    required this.booth,
    required this.camera,
    required this.backend,
    this.workflow = 'vangogh_vid2vid',
  });

  final BoothController booth;
  final CameraService camera;
  final BackendClient backend;

  AppPhase phase = AppPhase.attract;

  // guest
  String name = '';
  String email = '';
  bool consent = false;

  // capture config
  SpinDir dir = SpinDir.ccw;
  int speed = 5;
  int spinSecs = 8;
  String workflow;

  // look catalog (for the style picker); starts with the offline fallback.
  List<LookFamily> catalog = kFallbackCatalog;

  void setWorkflow(String id) {
    // ignore picks for looks the backend reported unavailable
    final opt = catalog.expand((f) => f.items).where((o) => o.id == id);
    if (opt.isNotEmpty && !opt.first.available) return;
    workflow = id;
    notifyListeners();
  }

  /// Pull the live catalog from the backend; keep the fallback on any error.
  Future<void> loadWorkflows() async {
    final remote = await backend.fetchWorkflows();
    if (remote.isNotEmpty) {
      catalog = remote;
      final all = remote.expand((f) => f.items).toList();
      final current = all.where((o) => o.id == workflow);
      // if the chosen look is gone or now unavailable, fall back to the first
      // available one.
      if (current.isEmpty || !current.first.available) {
        final firstOk = all.where((o) => o.available);
        if (firstOk.isNotEmpty) workflow = firstOk.first.id;
      }
      notifyListeners();
    }
  }

  // processing/result
  double progress = 0;
  String? previewUrl;
  String? resultUrl; // remote URL (for the QR)
  String? resultLocalPath; // downloaded mp4 (for in-app playback)
  bool showQr = false; // result screen: false = video, true = QR
  String? error;
  String? _videoPath;

  Future<void> init() async {
    try {
      await camera.init();
    } catch (e) {
      debugPrint('camera init failed: $e');
    }
    // connect the booth in the background so it's ready by capture time
    unawaited(booth.connect());
    // fetch the live look catalog (falls back to kFallbackCatalog on error)
    unawaited(loadWorkflows());
  }

  void go(AppPhase p) {
    phase = p;
    notifyListeners();
  }

  void setGuest({String? name, String? email, bool? consent}) {
    if (name != null) this.name = name;
    if (email != null) this.email = email;
    if (consent != null) this.consent = consent;
    notifyListeners();
  }

  void reset() {
    name = '';
    email = '';
    consent = false;
    progress = 0;
    previewUrl = null;
    resultUrl = null;
    resultLocalPath = null;
    showQr = false;
    error = null;
    _videoPath = null;
    phase = AppPhase.attract;
    notifyListeners();
  }

  void goToQr() {
    showQr = true;
    notifyListeners();
  }

  void goToVideo() {
    showQr = false;
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
      await backend.uploadJob(
        filePath: _videoPath!,
        name: name,
        email: email,
        consent: consent,
        workflow: workflow,
        direction: dir == SpinDir.cw ? 'clock' : 'counter_clock',
        speed: speed,
        durationSeconds: spinSecs,
      );
      progress = 1;
    } catch (e) {
      error = 'processing failed: $e';
    }
    go(AppPhase.result);
  }
}
