import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import 'camera_service.dart';

class RealCameraWindows implements CameraService {
  CameraController? _controller;
  Future<void>? _initFuture;
  CameraDescription? _selected;

  Future<void> _ensureInitialized() {
    final pending = _initFuture;
    if (pending != null) return pending;
    final next = _initialize();
    _initFuture = next;
    return next;
  }

  Future<void> _initialize() async {
    try {
      final existing = _controller;
      if (existing != null && existing.value.isInitialized) return;

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw StateError('No Windows camera was reported by Windows 11.');
      }

      final selected = _selectCamera(cameras);
      debugPrint(
        'Windows cameras: ${cameras.map((c) => c.name).join(', ')}; '
        'selected: ${selected.name}',
      );

      final controller = CameraController(
        selected,
        ResolutionPreset.high,
        enableAudio: false,
      );

      _selected = selected;
      _controller = controller;
      await controller.initialize();
    } catch (_) {
      _initFuture = null;
      rethrow;
    }
  }

  CameraDescription _selectCamera(List<CameraDescription> cameras) {
    for (final camera in cameras) {
      if (camera.lensDirection == CameraLensDirection.front) return camera;
    }
    for (final camera in cameras) {
      if (camera.lensDirection == CameraLensDirection.external) return camera;
    }
    return cameras.first;
  }

  @override
  Future<void> init() => _ensureInitialized();

  @override
  Future<void> startPreview() => _ensureInitialized();

  @override
  Future<void> stopPreview() async {
    // Keep the Windows camera open between preview, countdown, and capture.
  }

  @override
  Future<void> startRecording() async {
    await _ensureInitialized();
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      throw StateError('Windows camera is not initialized.');
    }
    if (controller.value.isRecordingVideo) return;
    await controller.startVideoRecording();
  }

  @override
  Future<String> stopRecording() async {
    final controller = _controller;
    if (controller == null || !controller.value.isRecordingVideo) {
      throw StateError('Windows camera is not recording.');
    }
    final file = await controller.stopVideoRecording();
    return file.path;
  }

  @override
  Widget buildPreview() => _WindowsCameraPreview(service: this);

  @override
  void dispose() {
    _controller?.dispose();
    _controller = null;
    _initFuture = null;
  }
}

class _WindowsCameraPreview extends StatefulWidget {
  const _WindowsCameraPreview({required this.service});

  final RealCameraWindows service;

  @override
  State<_WindowsCameraPreview> createState() => _WindowsCameraPreviewState();
}

class _WindowsCameraPreviewState extends State<_WindowsCameraPreview> {
  late Future<void> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.service._ensureInitialized();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const ColoredBox(
            color: Colors.black,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Brand.redBright),
                  SizedBox(height: 12),
                  Text(
                    'detecting Windows camera...',
                    style: TextStyle(color: Colors.white54),
                  ),
                ],
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          return ColoredBox(
            color: Colors.black,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.videocam_off,
                      size: 56,
                      color: Colors.white38,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Windows camera unavailable: ${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white54),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final controller = widget.service._controller;
        if (controller == null || !controller.value.isInitialized) {
          return const ColoredBox(
            color: Colors.black,
            child: Center(
              child: Text(
                'Windows camera not ready',
                style: TextStyle(color: Colors.white54),
              ),
            ),
          );
        }

        final selected = widget.service._selected?.name;
        return Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: Colors.black,
              child: Center(child: CameraPreview(controller)),
            ),
            if (selected != null)
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Text(
                      selected,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
