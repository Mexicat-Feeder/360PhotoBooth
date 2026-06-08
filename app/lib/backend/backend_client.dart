import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class StyleOption {
  StyleOption({required this.id, required this.label, required this.previewUrl});
  final String id;
  final String label;
  final String previewUrl;
}

class JobStatus {
  JobStatus({
    required this.status,
    required this.progress,
    required this.styles,
    this.resultUrl,
    this.error,
  });
  final String status; // previewing|choose|rendering|done|failed
  final double progress;
  final List<StyleOption> styles;
  final String? resultUrl;
  final String? error;

  bool get choosing => status == 'choose';
  bool get done => status == 'done';
  bool get failed => status == 'failed';
}

/// Talks to the booth backend (mock or real ComfyUI broker — same API).
class BackendClient {
  BackendClient(this.baseUrl);
  final String baseUrl;

  Future<String> createJob(String filePath, String name, String email) async {
    final req = http.MultipartRequest('POST', Uri.parse('$baseUrl/jobs'))
      ..fields['name'] = name
      ..fields['email'] = email
      ..files.add(await http.MultipartFile.fromPath('file', filePath));
    final s = await req.send();
    final body = await s.stream.bytesToString();
    if (s.statusCode >= 400) throw Exception('upload failed: $body');
    return (jsonDecode(body) as Map<String, dynamic>)['job_id'] as String;
  }

  Future<JobStatus> getStatus(String jobId) async {
    final r = await http.get(Uri.parse('$baseUrl/jobs/$jobId'));
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    final styles = ((j['styles'] as List?) ?? [])
        .map((e) => StyleOption(
              id: e['id'] as String,
              label: e['label'] as String,
              previewUrl: e['preview_url'] as String,
            ))
        .toList();
    return JobStatus(
      status: j['status'] as String? ?? 'failed',
      progress: ((j['progress'] as num?) ?? 0).toDouble(),
      styles: styles,
      resultUrl: j['result_url'] as String?,
      error: j['error'] as String?,
    );
  }

  Future<void> selectStyle(String jobId, String styleId) async {
    final r = await http.post(Uri.parse('$baseUrl/jobs/$jobId/select'),
        body: {'style': styleId});
    if (r.statusCode >= 400) throw Exception('select failed: ${r.body}');
  }

  Future<List<int>> download(String url) async {
    final r = await http.get(Uri.parse(url));
    return r.bodyBytes;
  }
}
