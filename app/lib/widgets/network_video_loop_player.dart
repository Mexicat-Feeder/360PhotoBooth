import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../theme.dart';
import 'preview_video_cache.dart';
import 'video_loop_player.dart';

class NetworkVideoLoopPlayer extends StatefulWidget {
  const NetworkVideoLoopPlayer({super.key, required this.url});

  final String url;

  static void prefetchAll(Iterable<String> urls) {
    for (final url in urls) {
      unawaited(_prefetch(url));
    }
  }

  static void cancelPendingDownloads() {
    PreviewVideoCache.instance.cancelPending();
  }

  static Future<void> _prefetch(String url) async {
    try {
      final file = await PreviewVideoCache.instance.get(url);
      if (_usesFramePreviewOnThisPlatform) {
        await VideoLoopPlayer.precacheFrames(file.path, fps: 12);
      }
    } catch (_) {
      // The visible player will surface an error if the selected preview fails.
    }
  }

  static bool get _usesFramePreviewOnThisPlatform =>
      Platform.isWindows || Platform.isLinux;

  @override
  State<NetworkVideoLoopPlayer> createState() => _NetworkVideoLoopPlayerState();
}

class _NetworkVideoLoopPlayerState extends State<NetworkVideoLoopPlayer> {
  VideoPlayerController? _controller;
  String? _framePreviewPath;
  String? _error;
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant NetworkVideoLoopPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final token = ++_loadToken;
    final old = _controller;
    if (mounted) {
      setState(() {
        _controller = null;
        _framePreviewPath = null;
        _error = null;
      });
    }
    await old?.dispose();

    try {
      final file = await PreviewVideoCache.instance.get(widget.url);

      if (_usesFramePreview) {
        if (!mounted || token != _loadToken) return;
        setState(() => _framePreviewPath = file.path);
        return;
      }

      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0);
      await controller.play();

      if (!mounted || token != _loadToken) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (e) {
      if (mounted && token == _loadToken) {
        setState(() => _error = '$e');
      }
    }
  }

  bool get _usesFramePreview =>
      NetworkVideoLoopPlayer._usesFramePreviewOnThisPlatform;

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final framePreviewPath = _framePreviewPath;
    if (_error != null) {
      return const Center(
        child: Icon(Icons.videocam_off, color: Colors.white38, size: 34),
      );
    }
    if (framePreviewPath != null) {
      return VideoLoopPlayer(
        key: ValueKey(framePreviewPath),
        path: framePreviewPath,
        fps: 12,
        fit: BoxFit.contain,
      );
    }
    if (controller == null || !controller.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Brand.redBright),
      );
    }
    return FittedBox(
      fit: BoxFit.contain,
      child: SizedBox(
        width: controller.value.size.width,
        height: controller.value.size.height,
        child: VideoPlayer(controller),
      ),
    );
  }

  @override
  void dispose() {
    _loadToken++;
    _controller?.dispose();
    super.dispose();
  }
}
