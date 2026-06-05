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

/// Talks to the backend (mock locally now; the real AMD box later — same API).
class BackendClient {
  BackendClient(this.baseUrl);
  final String baseUrl;

  Future<String> uploadJob(String filePath, String name, String email) async {
    final req = http.MultipartRequest('POST', Uri.parse('$baseUrl/jobs'))
      ..fields['name'] = name
      ..fields['email'] = email
      ..files.add(await http.MultipartFile.fromPath('file', filePath));
    final streamed = await req.send();
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode >= 400) {
      throw Exception('upload failed (${streamed.statusCode}): $body');
    }
    return (jsonDecode(body) as Map<String, dynamic>)['job_id'] as String;
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
}
