import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import 'camera_service.dart';

class RealCameraAndroid implements CameraService {
  CameraController? _controller;
  Future<void>? _initFuture;

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
        throw StateError('No Android camera was reported by the device.');
      }

      final selected = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        selected,
        ResolutionPreset.high,
        enableAudio: false,
      );

      _controller = controller;
      await controller.initialize();
    } catch (_) {
      _initFuture = null;
      rethrow;
    }
  }

  @override
  Future<void> init() => _ensureInitialized();

  @override
  Future<void> startPreview() => _ensureInitialized();

  @override
  Future<void> stopPreview() async {
    // Keep the Android controller alive while moving from preview to countdown
    // to capture. Releasing it here would force a slow reopen before recording.
  }

  @override
  Future<void> startRecording() async {
    await _ensureInitialized();
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      throw StateError('Android camera is not initialized.');
    }
    if (controller.value.isRecordingVideo) return;
    await controller.startVideoRecording();
  }

  @override
  Future<String> stopRecording() async {
    final controller = _controller;
    if (controller == null || !controller.value.isRecordingVideo) {
      throw StateError('Android camera is not recording.');
    }
    final file = await controller.stopVideoRecording();
    return file.path;
  }

  @override
  Widget buildPreview() => _AndroidCameraPreview(service: this);

  @override
  void dispose() {
    _controller?.dispose();
    _controller = null;
    _initFuture = null;
  }
}

class _AndroidCameraPreview extends StatefulWidget {
  const _AndroidCameraPreview({required this.service});

  final RealCameraAndroid service;

  @override
  State<_AndroidCameraPreview> createState() => _AndroidCameraPreviewState();
}

class _AndroidCameraPreviewState extends State<_AndroidCameraPreview> {
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
                    'starting camera...',
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
                      'Camera unavailable: ${snapshot.error}',
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
                'camera not ready',
                style: TextStyle(color: Colors.white54),
              ),
            ),
          );
        }

        return ColoredBox(
          color: Colors.black,
          child: Center(child: CameraPreview(controller)),
        );
      },
    );
  }
}
