import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

class PreviewVideoCache {
  PreviewVideoCache._();

  static final PreviewVideoCache instance = PreviewVideoCache._();

  final Map<String, Future<File>> _downloads = {};
  final Set<http.Client> _clients = {};

  Future<File> get(String url) {
    return _downloads.putIfAbsent(url, () => _download(url));
  }

  void prefetchAll(Iterable<String> urls) {
    for (final url in urls) {
      unawaited(get(url).then((_) {}).catchError((_) {}));
    }
  }

  void cancelPending() {
    for (final client in _clients.toList()) {
      client.close();
    }
    _clients.clear();
  }

  Future<File> _download(String url) async {
    final uri = Uri.parse(url);
    final file = File(_cachePathFor(uri));
    try {
      if (await _isUsable(file)) return file;

      final temp = File(
        '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
      );
      try {
        final client = http.Client();
        _clients.add(client);
        final response = await client
            .get(uri)
            .timeout(const Duration(seconds: 45))
            .whenComplete(() {
              _clients.remove(client);
              client.close();
            });
        if (response.statusCode >= 400) {
          throw StateError('preview fetch failed: ${response.statusCode}');
        }
        if (response.bodyBytes.isEmpty) {
          throw StateError('preview fetch returned an empty file');
        }

        await temp.writeAsBytes(response.bodyBytes, flush: true);
        if (await file.exists()) {
          await file.delete();
        }
        return temp.rename(file.path);
      } catch (_) {
        if (await temp.exists()) {
          await temp.delete();
        }
        rethrow;
      }
    } catch (_) {
      _downloads.remove(url);
      rethrow;
    }
  }

  Future<bool> _isUsable(File file) async {
    try {
      return await file.exists() && await file.length() > 0;
    } catch (_) {
      return false;
    }
  }

  String _cachePathFor(Uri uri) {
    final key = _stableHash(uri.toString()).toRadixString(16);
    return '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'booth_preview_$key.mp4';
  }

  int _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash;
  }
}
