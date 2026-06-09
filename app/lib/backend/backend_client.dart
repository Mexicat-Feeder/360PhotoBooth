import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class JobProgress {
  JobProgress({
    required this.progress,
    required this.status,
    this.previewUrl,
    this.resultUrl,
    this.error,
    this.emailStatus,
    this.emailError,
  });

  final double progress;
  final String status;
  final String? previewUrl;
  final String? resultUrl;
  final String? error;
  final String? emailStatus;
  final String? emailError;

  bool get done => status == 'done';
  bool get failed => status == 'failed';
}

class PresetPreview {
  PresetPreview({
    required this.id,
    required this.name,
    required this.description,
    this.previewUrl,
  });

  final String id;
  final String name;
  final String description;
  final String? previewUrl;

  factory PresetPreview.fromJson(Map<String, dynamic> json) => PresetPreview(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String,
    previewUrl: json['preview_url'] as String?,
  );
}

class PreviewJobProgress {
  PreviewJobProgress({
    required this.progress,
    required this.status,
    required this.presets,
    this.error,
  });

  final double progress;
  final String status;
  final List<PresetPreview> presets;
  final String? error;

  bool get done => status == 'done';
  bool get failed => status == 'failed';
}

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

  Future<String> createPreviewJob({
    required String filePath,
    required String name,
    required String email,
    required bool consent,
    required String workflow,
    required String direction,
    required int speed,
    required int durationSeconds,
  }) async {
    final req =
        http.MultipartRequest('POST', Uri.parse('$baseUrl/preview-jobs'))
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
      throw Exception('preview upload failed (${streamed.statusCode}): $body');
    }
    return (jsonDecode(body) as Map<String, dynamic>)['preview_job_id']
        as String;
  }

  Stream<PreviewJobProgress> pollPreviewJob(String previewJobId) async* {
    while (true) {
      final r = await http.get(
        Uri.parse('$baseUrl/preview-jobs/$previewJobId'),
      );
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final presets = ((j['presets'] as List?) ?? [])
          .cast<Map<String, dynamic>>()
          .map(PresetPreview.fromJson)
          .map(
            (p) => PresetPreview(
              id: p.id,
              name: p.name,
              description: p.description,
              previewUrl: p.previewUrl == null ? null : absolute(p.previewUrl!),
            ),
          )
          .toList();
      final p = PreviewJobProgress(
        progress: (j['progress'] as num).toDouble(),
        status: j['status'] as String,
        presets: presets,
        error: j['error'] as String?,
      );
      yield p;
      if (p.done || p.failed) break;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }

  Future<String> finalizePreviewJob(
    String previewJobId,
    String presetId,
  ) async {
    final r = await http.post(
      Uri.parse('$baseUrl/preview-jobs/$previewJobId/finalize'),
      body: {'preset_id': presetId},
    );
    if (r.statusCode >= 400) {
      throw Exception('finalize failed (${r.statusCode}): ${r.body}');
    }
    return (jsonDecode(r.body) as Map<String, dynamic>)['job_id'] as String;
  }

  Stream<JobProgress> pollProgress(String jobId) async* {
    while (true) {
      final r = await http.get(Uri.parse('$baseUrl/jobs/$jobId'));
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final p = JobProgress(
        progress: (j['progress'] as num).toDouble(),
        status: j['status'] as String,
        previewUrl: j['preview_url'] as String?,
        resultUrl: j['result_url'] as String?,
        error: j['error'] as String?,
        emailStatus: j['email_status'] as String?,
        emailError: j['email_error'] as String?,
      );
      yield p;
      if (p.done || p.failed) break;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }

  String absolute(String pathOrUrl) {
    final base = Uri.parse(baseUrl);
    final parsed = Uri.tryParse(pathOrUrl);
    if (parsed != null && parsed.hasScheme) {
      return base.replace(path: parsed.path, query: parsed.query).toString();
    }
    return base.resolve(pathOrUrl).toString();
  }

  Future<List<int>> download(String url) async {
    final r = await http.get(Uri.parse(url));
    return r.bodyBytes;
  }
}
