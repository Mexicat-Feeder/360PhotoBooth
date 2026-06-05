import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme.dart';
import 'camera_service.dart';

/// Linux webcam capture via ffmpeg (the `camera` plugin has no Linux desktop
/// support). Live preview writes a continuously-updated JPEG that the preview
/// widget polls; recording writes an H.264 mp4 (finalized on SIGINT).
class RealCameraLinux implements CameraService {
  RealCameraLinux({this.device = '/dev/video0'});
  final String device;

  late final Directory _dir;
  late final String _previewPath;
  late final String _recordPath;
  Process? _preview;
  Process? _record;

  String get previewPath => _previewPath;

  @override
  Future<void> init() async {
    _dir = Directory.systemTemp.createTempSync('booth_cam_');
    _previewPath = '${_dir.path}/preview.jpg';
    _recordPath = '${_dir.path}/capture.mp4';
  }

  @override
  Future<void> startPreview() async {
    if (_record != null || _preview != null) return;
    try {
      _preview = await Process.start('ffmpeg', [
        '-hide_banner', '-loglevel', 'error',
        '-f', 'v4l2', '-framerate', '15', '-video_size', '640x480',
        '-i', device,
        '-vf', 'fps=12', '-q:v', '6', '-update', '1', '-y', _previewPath,
      ]);
    } catch (_) {
      _preview = null; // ffmpeg missing / device busy — preview just won't show
    }
  }

  @override
  Future<void> stopPreview() async {
    final p = _preview;
    _preview = null;
    if (p != null) {
      p.kill(ProcessSignal.sigint);
      await p.exitCode.timeout(const Duration(seconds: 3), onTimeout: () {
        p.kill(ProcessSignal.sigkill);
        return -1;
      });
    }
  }

  @override
  Future<void> startRecording() async {
    await stopPreview();
    _record = await Process.start('ffmpeg', [
      '-hide_banner', '-loglevel', 'error',
      '-f', 'v4l2', '-framerate', '24', '-video_size', '1280x720',
      '-i', device,
      // center-crop to square so the square AI output isn't distorted
      '-vf', 'crop=720:720',
      '-c:v', 'libx264', '-preset', 'veryfast', '-pix_fmt', 'yuv420p',
      '-movflags', '+faststart', '-y', _recordPath,
    ]);
  }

  @override
  Future<String> stopRecording() async {
    final p = _record;
    _record = null;
    if (p != null) {
      p.kill(ProcessSignal.sigint); // ffmpeg finalizes the mp4 on SIGINT
      await p.exitCode.timeout(const Duration(seconds: 8), onTimeout: () {
        p.kill(ProcessSignal.sigkill);
        return -1;
      });
    }
    return _recordPath;
  }

  @override
  Widget buildPreview() => _LivePreview(path: _previewPath);

  @override
  void dispose() {
    _preview?.kill(ProcessSignal.sigkill);
    _record?.kill(ProcessSignal.sigkill);
  }
}

class _LivePreview extends StatefulWidget {
  const _LivePreview({required this.path});
  final String path;

  @override
  State<_LivePreview> createState() => _LivePreviewState();
}

class _LivePreviewState extends State<_LivePreview> {
  Uint8List? _frame;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(milliseconds: 120), (_) {
      try {
        final f = File(widget.path);
        if (f.existsSync() && f.lengthSync() > 0) {
          final b = f.readAsBytesSync();
          if (mounted) setState(() => _frame = b);
        }
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_frame == null) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(color: Brand.redBright),
            SizedBox(height: 12),
            Text('starting camera…', style: TextStyle(color: Colors.white54)),
          ]),
        ),
      );
    }
    return Image.memory(
      _frame!,
      gaplessPlayback: true,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
    );
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }
}
