import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class JobProgress {
  JobProgress({
    required this.progress,
    required this.status,
    this.previewUrl,
    this.resultUrl,
  });
  final double progress; // 0..1
  final String status; // queued | generating | done | failed
  final String? previewUrl;
  final String? resultUrl;

  bool get done => status == 'done';
  bool get failed => status == 'failed';
}

/// One selectable look in the picker. Mirrors the backend GET /workflows entry.
class LookOption {
  const LookOption({
    required this.id,
    required this.label,
    required this.family,
    required this.blurb,
    this.available = true,
    this.reason,
  });
  final String id; // == workflow file stem sent back on upload
  final String label;
  final String family; // style | background | motion
  final String blurb;
  final bool available; // its ComfyUI nodes are installed
  final String? reason; // why unavailable (e.g. "needs ComfyUI-RMBG")
}

/// A family group of looks (e.g. "AI Styles").
class LookFamily {
  const LookFamily({
    required this.family,
    required this.label,
    required this.items,
  });
  final String family;
  final String label;
  final List<LookOption> items;
}

/// Offline-first fallback so the picker always has content even if /workflows
/// is unreachable. Kept in sync with booth_backend/catalog.py.
const List<LookFamily> kFallbackCatalog = [
  LookFamily(family: 'style', label: 'AI Styles', items: [
    LookOption(id: 'vangogh_vid2vid', label: 'Van Gogh', family: 'style', blurb: 'Swirling impasto oil — the hero look'),
    LookOption(id: 'anime', label: 'Anime', family: 'style', blurb: 'Clean cel-shaded anime'),
    LookOption(id: 'watercolor', label: 'Watercolor', family: 'style', blurb: 'Soft washed painting'),
    LookOption(id: 'comic', label: 'Comic Book', family: 'style', blurb: 'Bold ink & flat color'),
    LookOption(id: 'cyberpunk', label: 'Cyberpunk', family: 'style', blurb: 'Neon rain, blade-runner glow'),
    LookOption(id: 'ukiyoe', label: 'Ukiyo-e', family: 'style', blurb: 'Japanese woodblock print'),
    LookOption(id: 'popart', label: 'Pop Art', family: 'style', blurb: 'Warhol screenprint pop'),
    LookOption(id: 'claymation', label: 'Claymation', family: 'style', blurb: 'Sculpted stop-motion clay'),
    LookOption(id: 'pencil', label: 'Pencil Sketch', family: 'style', blurb: 'Hand-drawn graphite'),
  ]),
  LookFamily(family: 'background', label: 'Backgrounds', items: [
    LookOption(id: 'bg_black', label: 'Spotlight', family: 'background', blurb: 'Guest on solid black'),
    LookOption(id: 'bg_white', label: 'Studio', family: 'background', blurb: 'Guest on clean white'),
    LookOption(id: 'bg_magenta', label: 'Neon Pop', family: 'background', blurb: 'Guest on neon magenta'),
    LookOption(id: 'bg_blur', label: 'Blurred Backdrop', family: 'background', blurb: 'Guest sharp, background blurred'),
    LookOption(id: 'bg_image', label: 'Custom Backdrop', family: 'background', blurb: 'Guest on your own image'),
  ]),
  LookFamily(family: 'motion', label: 'Motion & Format', items: [
    LookOption(id: 'slowmo', label: 'Slow Motion', family: 'motion', blurb: 'Buttery RIFE slow-mo'),
    LookOption(id: 'boomerang', label: 'Boomerang', family: 'motion', blurb: 'Forward then reverse loop'),
    LookOption(id: 'vertical', label: 'Vertical 9:16', family: 'motion', blurb: 'Ready for Reels/TikTok'),
    LookOption(id: 'slowmo_vert', label: 'Slow-Mo Vertical', family: 'motion', blurb: 'Slow-mo + 9:16 combo'),
  ]),
];

/// Talks to the backend (mock locally now; the real AMD box later — same API).
class BackendClient {
  BackendClient(this.baseUrl);
  final String baseUrl;

  Future<String> uploadJob({
    required String filePath,
    required String name,
    required String email,
    required bool consent,
    required String workflow,
    required String direction,
    required int speed,
    required int durationSeconds,
  }) async {
    final req = http.MultipartRequest('POST', Uri.parse('$baseUrl/jobs'))
      ..fields['name'] = name
      ..fields['email'] = email
      ..fields['consent'] = consent.toString()
      ..fields['workflow'] = workflow
      ..fields['direction'] = direction
      ..fields['speed'] = speed.toString()
      ..fields['duration_seconds'] = durationSeconds.toString()
      ..files.add(await http.MultipartFile.fromPath('file', filePath));
    final streamed = await req.send();
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode >= 400) {
      throw Exception('upload failed (${streamed.statusCode}): $body');
    }
    return (jsonDecode(body) as Map<String, dynamic>)['job_id'] as String;
  }

  /// Fetches the look catalog (grouped families). Returns [] on any error so the
  /// caller can fall back to kFallbackCatalog.
  Future<List<LookFamily>> fetchWorkflows() async {
    try {
      final r = await http
          .get(Uri.parse('$baseUrl/workflows'))
          .timeout(const Duration(seconds: 4));
      if (r.statusCode >= 400) return const [];
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final fams = (j['families'] as List?) ?? const [];
      return fams.map((f) {
        final m = f as Map<String, dynamic>;
        final items = (m['items'] as List? ?? const [])
            .map((e) => LookOption(
                  id: e['id'] as String,
                  label: e['label'] as String,
                  family: e['family'] as String,
                  blurb: (e['blurb'] as String?) ?? '',
                  available: (e['available'] as bool?) ?? true,
                  reason: e['reason'] as String?,
                ))
            .toList();
        return LookFamily(
          family: m['family'] as String,
          label: m['label'] as String,
          items: items,
        );
      }).where((f) => f.items.isNotEmpty).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Polls job status until done/failed.
  Stream<JobProgress> pollProgress(String jobId) async* {
    while (true) {
      final r = await http.get(Uri.parse('$baseUrl/jobs/$jobId'));
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final p = JobProgress(
        progress: (j['progress'] as num).toDouble(),
        status: j['status'] as String,
        previewUrl: j['preview_url'] as String?,
        resultUrl: j['result_url'] as String?,
      );
      yield p;
      if (p.done || p.failed) break;
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
  }

  String absolute(String pathOrUrl) =>
      pathOrUrl.startsWith('http') ? pathOrUrl : '$baseUrl$pathOrUrl';

  Future<List<int>> download(String url) async {
    final r = await http.get(Uri.parse(url));
    return r.bodyBytes;
  }
}
