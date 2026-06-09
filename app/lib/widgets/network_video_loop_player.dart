import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.url),
      );
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0);
      await controller.play();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
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
    _controller?.dispose();
    super.dispose();
  }
}
