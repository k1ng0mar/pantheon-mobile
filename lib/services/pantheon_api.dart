import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/approval.dart';
import '../models/gateway_status.dart';
import '../models/overview.dart';
import '../models/pantheon_run.dart';
import '../models/scheduled_job.dart';
import '../models/usage_stats.dart';

class PantheonApiException implements Exception {
  final int status;
  final String body;
  PantheonApiException(this.status, this.body);
  @override
  String toString() => body.isEmpty
      ? 'Pantheon API error $status'
      : 'Pantheon API error $status: $body';
}

class PantheonAuthException extends PantheonApiException {
  PantheonAuthException() : super(401, 'unauthorized');
  @override
  String toString() => 'Wrong or missing dashboard token.';
}

class PantheonUnreachableException implements Exception {
  final String message;
  PantheonUnreachableException(this.message);
  @override
  String toString() => message;
}

/// HTTP client for the Pantheon dashboard API
/// (`pantheon dashboard --bind 0.0.0.0 --port 7171`).
class PantheonApi {
  PantheonApi({required this.baseUrl, required this.token});

  final String baseUrl;
  final String token;

  static const _timeout = Duration(seconds: 15);

  Map<String, String> get _headers => {'x-pantheon-token': token};

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$base$path').replace(queryParameters: query);
  }

  Future<Map<String, dynamic>> _get(String path,
      [Map<String, String>? query]) async {
    http.Response res;
    try {
      res = await http
          .get(_uri(path, query), headers: _headers)
          .timeout(_timeout);
    } on TimeoutException {
      throw PantheonUnreachableException('Timed out reaching $baseUrl.');
    } catch (e) {
      throw PantheonUnreachableException('Cannot reach $baseUrl ($e).');
    }
    return _decode(res);
  }

  Future<Map<String, dynamic>> _post(String path,
      [Map<String, dynamic>? body]) async {
    http.Response res;
    try {
      res = await http
          .post(_uri(path),
              headers: {..._headers, 'Content-Type': 'application/json'},
              body: jsonEncode(body ?? {}))
          .timeout(_timeout);
    } on TimeoutException {
      throw PantheonUnreachableException('Timed out reaching $baseUrl.');
    } catch (e) {
      throw PantheonUnreachableException('Cannot reach $baseUrl ($e).');
    }
    return _decode(res);
  }

  Map<String, dynamic> _decode(http.Response res) {
    if (res.statusCode == 401) throw PantheonAuthException();
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw PantheonApiException(res.statusCode, _serverMessage(res.body));
    }
    final v = jsonDecode(res.body);
    return v is Map ? v.cast<String, dynamic>() : {'value': v};
  }

  /// The dashboard wraps errors as {"ok": false, "error": {"code": "…",
  /// "message": "…"}} — surface the real message instead of a raw body dump.
  static String _serverMessage(String body) {
    try {
      final v = jsonDecode(body);
      if (v is Map) {
        final err = v['error'];
        if (err is Map && err['message'] is String) {
          return err['message'] as String;
        }
        if (v['message'] is String) return v['message'] as String;
      }
    } catch (_) {}
    return body.length > 200 ? '${body.substring(0, 200)}…' : body;
  }

  Future<Overview> overview() async =>
      Overview.fromJson(await _get('/api/overview'));

  Future<GatewayStatus> gatewayStatus() async =>
      GatewayStatus.fromJson(await _get('/api/gateway/status'));

  Future<List<PantheonRun>> runs(
      {String? q, String? status, int limit = 100}) async {
    final query = <String, String>{'limit': '$limit'};
    if (q != null && q.isNotEmpty) query['q'] = q;
    if (status != null && status.isNotEmpty) query['status'] = status;
    final j = await _get('/api/runs', query);
    final list = (j['runs'] as List?) ?? [];
    return list
        .whereType<Map>()
        .map((e) => PantheonRun.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<PantheonRun> runDetail(String id) async =>
      PantheonRun.fromJson(await _get('/api/runs/${Uri.encodeComponent(id)}'));

  Future<List<Approval>> approvals() async {
    final j = await _get('/api/approvals');
    final list = (j['approvals'] as List?) ?? [];
    return list
        .whereType<Map>()
        .map((e) => Approval.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  /// Grant or deny a pending approval. `id` is the scope string from [Approval.id].
  Future<void> decideApproval(String id, bool grant) async {
    await _post(
        '/api/approvals/${Uri.encodeComponent(id)}/${grant ? 'grant' : 'deny'}');
  }

  Future<UsageStats> stats({int days = 30}) async =>
      UsageStats.fromJson(await _get('/api/stats', {'days': '$days'}));

  Future<List<ScheduledJob>> scheduleJobs() async {
    final j = await _get('/api/schedule/jobs');
    final list = (j['jobs'] as List?) ?? [];
    return list
        .whereType<Map>()
        .map((e) => ScheduledJob.fromJson(e.cast<String, dynamic>()))
        .toList();
  }
}
