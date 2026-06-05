import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme.dart';

/// Plays a local mp4 by extracting its frames with ffmpeg and looping them as
/// images. Lightweight, no video_player/libmpv dependency — fine for the short
/// stylized booth clip (no audio needed). Loops forever.
class VideoLoopPlayer extends StatefulWidget {
  const VideoLoopPlayer({super.key, required this.path, this.fps = 12});
  final String path;
  final int fps;

  @override
  State<VideoLoopPlayer> createState() => _VideoLoopPlayerState();
}

class _VideoLoopPlayerState extends State<VideoLoopPlayer> {
  final List<Uint8List> _frames = [];
  int _i = 0;
  Timer? _t;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final dir = Directory.systemTemp.createTempSync('booth_play_');
      final res = await Process.run('ffmpeg', [
        '-hide_banner', '-loglevel', 'error', '-i', widget.path,
        '-vf', 'fps=${widget.fps}', '${dir.path}/f_%03d.jpg',
      ]);
      if (res.exitCode != 0) {
        setState(() => _error = 'decode failed');
        return;
      }
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.jpg'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      for (final f in files) {
        _frames.add(f.readAsBytesSync());
      }
      if (_frames.isEmpty) {
        setState(() => _error = 'no frames');
        return;
      }
      _t = Timer.periodic(
        Duration(milliseconds: (1000 / widget.fps).round()),
        (_) => setState(() => _i = (_i + 1) % _frames.length),
      );
      setState(() {});
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
          child: Text('preview unavailable',
              style: const TextStyle(color: Colors.white54)));
    }
    if (_frames.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: Brand.redBright));
    }
    return Image.memory(_frames[_i], gaplessPlayback: true, fit: BoxFit.cover,
        width: double.infinity, height: double.infinity);
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }
}
