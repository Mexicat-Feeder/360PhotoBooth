import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

import '../theme.dart';

class NetworkVideoLoopPlayer extends StatefulWidget {
  const NetworkVideoLoopPlayer({super.key, required this.url});

  final String url;

  @override
  State<NetworkVideoLoopPlayer> createState() => _NetworkVideoLoopPlayerState();
}

class _NetworkVideoLoopPlayerState extends State<NetworkVideoLoopPlayer> {
  VideoPlayerController? _controller;
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
        _error = null;
      });
    }
    await old?.dispose();

    try {
      final uri = Uri.parse(widget.url);
      final response = await http.get(uri).timeout(const Duration(seconds: 45));
      if (response.statusCode >= 400) {
        throw StateError('preview fetch failed: ${response.statusCode}');
      }
      if (response.bodyBytes.isEmpty) {
        throw StateError('preview fetch returned an empty file');
      }

      final file = File(_cachePathFor(uri));
      await file.writeAsBytes(response.bodyBytes, flush: true);

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

  String _cachePathFor(Uri uri) {
    final key = uri.toString().hashCode.toUnsigned(32).toRadixString(16);
    return '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'booth_preview_$key.mp4';
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_error != null) {
      return const Center(
        child: Icon(Icons.videocam_off, color: Colors.white38, size: 34),
      );
    }
    if (controller == null || !controller.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Brand.redBright),
      );
    }
    return FittedBox(
      fit: BoxFit.cover,
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
