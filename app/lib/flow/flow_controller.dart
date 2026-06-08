import 'dart:async';
import 'dart:io';

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
  processing, // generating the style previews
  stylePick,  // choose a style from the gallery
  rendering,  // rendering the chosen style as a full video
  result,     // play video -> QR
}

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

  String name = '';
  String email = '';

  SpinDir dir = SpinDir.ccw;
  int speed = 5;
  int spinSecs = 8;

  // job / styles / result
  String? jobId;
  List<StyleOption> styles = [];
  double progress = 0;
  String? resultUrl;
  String? resultLocalPath;
  bool showQr = false;
  String? error;
  String? _videoPath;

  Future<void> init() async {
    await camera.init();
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
    jobId = null;
    styles = [];
    progress = 0;
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

  /// Countdown finished: record + spin, then upload and generate the previews.
  Future<void> runCaptureAndProcess() async {
    go(AppPhase.capture);
    error = null;
    try {
      await camera.startRecording();
      await booth.spin(dir, speed, spinSecs);
      await Future<void>.delayed(Duration(seconds: spinSecs));
      await booth.stop();
      _videoPath = await camera.stopRecording();
    } catch (e) {
      _fail('capture failed: $e');
      return;
    }
    go(AppPhase.processing);
    await _generatePreviews();
  }

  Future<void> _generatePreviews() async {
    progress = 0;
    try {
      jobId = await backend.createJob(_videoPath!, name, email);
      while (true) {
        final s = await backend.getStatus(jobId!);
        progress = s.progress;
        notifyListeners();
        if (s.failed) return _fail(s.error ?? 'preview generation failed');
        if (s.choosing) {
          styles = s.styles;
          go(AppPhase.stylePick);
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 700));
      }
    } catch (e) {
      _fail('upload/preview failed: $e');
    }
  }

  Future<void> selectStyle(String styleId) async {
    go(AppPhase.rendering);
    progress = 0;
    try {
      await backend.selectStyle(jobId!, styleId);
      while (true) {
        final s = await backend.getStatus(jobId!);
        progress = s.progress;
        notifyListeners();
        if (s.failed) return _fail(s.error ?? 'render failed');
        if (s.done) {
          resultUrl = s.resultUrl;
          if (resultUrl != null) {
            final bytes = await backend.download(resultUrl!);
            final dir = Directory.systemTemp.createTempSync('booth_result_');
            final f = File('${dir.path}/result.mp4');
            await f.writeAsBytes(bytes);
            resultLocalPath = f.path;
          }
          go(AppPhase.result);
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 700));
      }
    } catch (e) {
      _fail('render failed: $e');
    }
  }

  void _fail(String msg) {
    error = msg;
    go(AppPhase.result);
  }
}
