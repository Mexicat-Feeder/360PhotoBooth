import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme.dart';

/// Plays a local mp4 by extracting its frames with ffmpeg and looping them as
/// images. Lightweight, no video_player/libmpv dependency — fine for the short
/// stylized booth clip (no audio needed). Loops forever.
class VideoLoopPlayer extends StatefulWidget {
  const VideoLoopPlayer({
    super.key,
    required this.path,
    this.fps = 12,
    this.fit = BoxFit.cover,
  });

  final String path;
  final int fps;
  final BoxFit fit;

  static Future<void> precacheFrames(String path, {int fps = 12}) async {
    await _VideoFrameCache.load(path, fps);
  }

  @override
  State<VideoLoopPlayer> createState() => _VideoLoopPlayerState();
}

class _VideoLoopPlayerState extends State<VideoLoopPlayer> {
  List<Uint8List> _frames = const [];
  int _i = 0;
  Timer? _t;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant VideoLoopPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path || oldWidget.fps != widget.fps) {
      _t?.cancel();
      _t = null;
      setState(() {
        _frames = const [];
        _i = 0;
        _error = null;
      });
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    try {
      final frames = await _VideoFrameCache.load(widget.path, widget.fps);
      if (!mounted) return;
      if (frames.isEmpty) {
        setState(() => _error = 'no frames');
        return;
      }
      _frames = frames;
      _t = Timer.periodic(Duration(milliseconds: (1000 / widget.fps).round()), (
        _,
      ) {
        if (!mounted) return;
        setState(() => _i = (_i + 1) % _frames.length);
      });
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Text(
          'preview unavailable',
          style: const TextStyle(color: Colors.white54),
        ),
      );
    }
    if (_frames.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: Brand.redBright),
      );
    }
    return Image.memory(
      _frames[_i],
      gaplessPlayback: true,
      fit: widget.fit,
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

class _VideoFrameCache {
  static final Map<String, Future<List<Uint8List>>> _frames = {};

  static Future<List<Uint8List>> load(String path, int fps) {
    final key = '$path::$fps';
    final existing = _frames[key];
    if (existing != null) return existing;

    final future = _extract(path, fps);
    _frames[key] = future;
    unawaited(
      future.catchError((_) {
        if (_frames[key] == future) {
          _frames.remove(key);
        }
        return <Uint8List>[];
      }),
    );
    return future;
  }

  static Future<List<Uint8List>> _extract(String path, int fps) async {
    final dir = Directory.systemTemp.createTempSync('booth_play_');
    try {
      final res = await Process.run('ffmpeg', [
        '-hide_banner',
        '-loglevel',
        'error',
        '-i',
        path,
        '-vf',
        'fps=$fps',
        '${dir.path}/f_%03d.jpg',
      ]);
      if (res.exitCode != 0) {
        throw StateError('decode failed');
      }

      final files =
          dir
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.jpg'))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));

      return [for (final file in files) file.readAsBytesSync()];
    } finally {
      unawaited(dir.delete(recursive: true).catchError((_) => dir));
    }
  }
}
