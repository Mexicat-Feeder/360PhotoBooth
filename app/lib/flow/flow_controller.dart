import 'dart:async';

import 'package:flutter/foundation.dart';

import '../backend/backend_client.dart';
import '../ble/booth_controller.dart';
import '../ble/booth_protocol.dart';
import '../camera/camera_service.dart';

enum AppPhase {
  attract,
  info,
  preview,
  countdown,
  capture,
  processing,
  preset,
  submitted,
  result,
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

  bool get hasName => name.trim().isNotEmpty;
  String get displayName => name.trim().isEmpty ? 'there' : name.trim();

  // capture config
  SpinDir dir = SpinDir.ccw;
  int speed = 5;
  int spinSecs = 8;
  String workflow;
  String? previewJobId;
  String? selectedPresetId;
  List<PresetPreview> presetPreviews = [];

  // processing/result
  double progress = 0;
  String processingTitle = 'Generating your video';
  String processingSubtitle = 'Running locally on AMD Ryzen AI';
  String? previewUrl;
  String? resultUrl; // remote URL (for the QR)
  String? resultLocalPath; // downloaded mp4 (for in-app playback)
  bool showQr = false; // result screen: false = video, true = QR
  String? error;
  String? _videoPath;
  Timer? _returnHomeTimer;

  Future<void> init() async {
    try {
      await camera.init();
    } catch (e) {
      debugPrint('camera init failed: $e');
    }
    // connect the booth in the background so it's ready by capture time
    unawaited(booth.connect());
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
    _returnHomeTimer?.cancel();
    _returnHomeTimer = null;
    name = '';
    email = '';
    consent = false;
    progress = 0;
    processingTitle = 'Generating your video';
    processingSubtitle = 'Running locally on AMD Ryzen AI';
    previewUrl = null;
    resultUrl = null;
    resultLocalPath = null;
    previewJobId = null;
    selectedPresetId = null;
    presetPreviews = [];
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
    await _preparePreviews();
  }

  Future<void> _preparePreviews() async {
    progress = 0;
    processingTitle = 'Generating preview looks';
    processingSubtitle = 'Making four short previews from your capture';
    notifyListeners();
    try {
      final id = await backend.createPreviewJob(
        filePath: _videoPath!,
        name: name,
        email: email,
        consent: consent,
        workflow: workflow,
        direction: dir == SpinDir.cw ? 'clock' : 'counter_clock',
        speed: speed,
        durationSeconds: spinSecs,
      );
      previewJobId = id;
      await for (final p in backend.pollPreviewJob(id)) {
        progress = p.progress;
        presetPreviews = p.presets;
        if (p.failed) {
          error = p.error ?? 'preview generation failed';
          break;
        }
        notifyListeners();
      }
      if (error == null) {
        selectedPresetId = presetPreviews.isNotEmpty
            ? presetPreviews.first.id
            : null;
        go(AppPhase.preset);
        return;
      }
    } catch (e) {
      error = 'preview generation failed: $e';
    }
    go(AppPhase.result);
  }

  Future<void> selectPresetAndProcess(String presetId) async {
    final id = previewJobId;
    if (id == null) {
      error = 'preview job missing';
      go(AppPhase.result);
      return;
    }

    selectedPresetId = presetId;
    progress = 0;
    resultUrl = null;
    resultLocalPath = null;
    error = null;
    processingTitle = 'Sending final job';
    processingSubtitle = 'Queueing the selected look for rendering';
    go(AppPhase.processing);

    try {
      await backend.finalizePreviewJob(id, presetId);
      progress = 1;
      go(AppPhase.submitted);
      _scheduleReturnHome();
    } catch (e) {
      error = 'final job submit failed: $e';
      go(AppPhase.result);
    }
  }

  void _scheduleReturnHome() {
    _returnHomeTimer?.cancel();
    _returnHomeTimer = Timer(const Duration(seconds: 4), () {
      _returnHomeTimer = null;
      if (phase == AppPhase.submitted) {
        reset();
      }
    });
  }
}
