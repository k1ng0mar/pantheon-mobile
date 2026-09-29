import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/approval.dart';
import '../models/config_doc.dart';
import '../models/env_key.dart';
import '../models/gateway_status.dart';
import '../models/log_tail.dart';
import '../models/mcp_server.dart';
import '../models/memory_entry.dart';
import '../models/overview.dart';
import '../models/pantheon_run.dart';
import '../models/plugin.dart';
import '../models/scheduled_job.dart';
import '../models/schedule_template.dart';
import '../models/skill.dart';
import '../models/usage_stats.dart';

/// Thrown when a message is sent to a run that already finished (HTTP 409).
class PantheonRunFinishedException extends PantheonApiException {
  PantheonRunFinishedException(String body) : super(409, body);
  @override
  String toString() => 'This session has finished; it can\'t take new messages.';
}

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

  Future<Map<String, dynamic>> _put(String path,
      [Map<String, dynamic>? body]) async {
    http.Response res;
    try {
      res = await http
          .put(_uri(path),
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

  Future<Map<String, dynamic>> _delete(String path) async {
    http.Response res;
    try {
      res = await http.delete(_uri(path), headers: _headers).timeout(_timeout);
    } on TimeoutException {
      throw PantheonUnreachableException('Timed out reaching $baseUrl.');
    } catch (e) {
      throw PantheonUnreachableException('Cannot reach $baseUrl ($e).');
    }
    return _decode(res);
  }

  /// Raw-bytes GET for download endpoints (config export).
  Future<List<int>> _getBytes(String path) async {
    http.Response res;
    try {
      res = await http.get(_uri(path), headers: _headers).timeout(_timeout);
    } on TimeoutException {
      throw PantheonUnreachableException('Timed out reaching $baseUrl.');
    } catch (e) {
      throw PantheonUnreachableException('Cannot reach $baseUrl ($e).');
    }
    if (res.statusCode == 401) throw PantheonAuthException();
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw PantheonApiException(res.statusCode, _serverMessage(res.body));
    }
    return res.bodyBytes;
  }

  Map<String, dynamic> _decode(http.Response res) {
    if (res.statusCode == 401) throw PantheonAuthException();
    if (res.statusCode == 409) {
      throw PantheonRunFinishedException(_serverMessage(res.body));
    }
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

  // ------------------------------------------------------------------
  // Chat: create a run, send a message into a running one.
  // ------------------------------------------------------------------

  /// Start a new run with an opening message. Returns the created run
  /// (same shape as `GET /api/runs/:id`).
  Future<PantheonRun> createRun(
      {required String message, String? title}) async {
    final body = <String, dynamic>{'message': message};
    if (title != null && title.isNotEmpty) body['title'] = title;
    return PantheonRun.fromJson(await _post('/api/runs', body));
  }

  /// Send a follow-up message into a live run. Throws
  /// [PantheonRunFinishedException] (HTTP 409) when the run is done.
  Future<void> sendRunMessage(String runId, String message) async {
    await _post('/api/runs/${Uri.encodeComponent(runId)}/message',
        {'message': message});
  }

  /// Delete a run from the ledger.
  Future<void> deleteRun(String id) async {
    await _delete('/api/runs/${Uri.encodeComponent(id)}');
  }

  // ------------------------------------------------------------------
  // Memory
  // ------------------------------------------------------------------

  Future<List<MemoryEntry>> memoryEntries({String? q, int limit = 200}) async {
    final query = <String, String>{'limit': '$limit'};
    if (q != null && q.isNotEmpty) query['q'] = q;
    final j = await _get('/api/memory', query);
    final list = (j['records'] as List?) ?? [];
    return list
        .whereType<Map>()
        .map((e) => MemoryEntry.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<MemoryEntry> addMemory({required String text, String? kind}) async {
    final body = <String, dynamic>{'text': text};
    if (kind != null && kind.isNotEmpty) body['kind'] = kind;
    final j = await _post('/api/memory', body);
    final entry = j['entry'];
    if (entry is Map) {
      return MemoryEntry.fromJson(entry.cast<String, dynamic>());
    }
    return MemoryEntry(
        key: text.length > 40 ? '${text.substring(0, 40)}…' : text,
        value: text,
        layer: 'agent',
        namespace: '');
  }

  // ------------------------------------------------------------------
  // Config
  // ------------------------------------------------------------------

  Future<ConfigDoc> getConfig() async =>
      ConfigDoc.fromJson(await _get('/api/config'));

  Future<List<ConfigField>> configSchema() async {
    final j = await _get('/api/config/schema');
    final list = (j['fields'] as List?) ?? [];
    return list
        .whereType<Map>()
        .map((e) => ConfigField.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  /// Apply dotted-path changes, e.g. {"model.provider": "openai"}.
  /// Returns the changed paths.
  Future<List<String>> putConfig(Map<String, dynamic> changes) async {
    final j =
        await _put('/api/config', {'changes': changes, 'confirm': true});
    final changed = (j['changed'] as List?) ?? [];
    return changed.map((e) => e.toString()).toList();
  }

  /// Export the raw config.toml bytes.
  Future<List<int>> exportConfig() => _getBytes('/api/config/export');

  Future<void> importConfig(String toml) async {
    await _post('/api/config/import', {'toml': toml, 'confirm': true});
  }

  // ------------------------------------------------------------------
  // Env / keys
  // ------------------------------------------------------------------

  Future<List<EnvKey>> envKeys() async {
    final j = await _get('/api/env');
    final list = (j['keys'] as List?) ?? [];
    return list
        .whereType<Map>()
        .map((e) => EnvKey.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<void> putEnv(String key, String value) async {
    await _put('/api/env', {
      'upserts': {key: value},
      'confirm': true,
    });
  }

  Future<void> deleteEnv(String key) async {
    await _delete('/api/env/${Uri.encodeComponent(key)}');
  }

  // ------------------------------------------------------------------
  // Logs
  // ------------------------------------------------------------------

  Future<LogTail> logs(
      {String source = 'agent',
      int tail = 200,
      String? level,
      String? grep}) async {
    final query = <String, String>{'source': source, 'tail': '$tail'};
    if (level != null && level.isNotEmpty) query['level'] = level;
    if (grep != null && grep.isNotEmpty) query['grep'] = grep;
    return LogTail.fromJson(await _get('/api/logs', query));
  }

  // ------------------------------------------------------------------
  // Skills
  // ------------------------------------------------------------------

  Future<List<Skill>> skills() async {
    final j = await _get('/api/skills');
    final list = (j['skills'] as List?) ?? [];
    return list
        .whereType<Map>()
        .map((e) => Skill.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  /// Toggle a skill; returns the new enabled state.
  Future<bool> toggleSkill(String name) async {
    final j =
        await _post('/api/skills/${Uri.encodeComponent(name)}/toggle');
    return j['enabled'] as bool? ?? true;
  }

  Future<void> importSkill(String url) async {
    await _post('/api/skills/import', {'url': url, 'confirm': true});
  }

  Future<void> deleteSkill(String name) async {
    await _delete('/api/skills/${Uri.encodeComponent(name)}');
  }

  // ------------------------------------------------------------------
  // MCP
  // ------------------------------------------------------------------

  /// Returns (groups, pendingApproval, note).
  Future<({List<McpServerGroup> groups, List<String> pending, String? note})>
      mcpServers() async {
    final j = await _get('/api/mcp/servers');
    final list = (j['servers'] as List?) ?? [];
    final groups = list
        .whereType<Map>()
        .map((e) => McpServerGroup.fromJson(e.cast<String, dynamic>()))
        .toList();
    final pending = (j['pending_approval'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
    return (groups: groups, pending: pending, note: j['note'] as String?);
  }

  Future<Map<String, dynamic>> mcpHealth() async =>
      await _get('/api/mcp/health');

  Future<void> addMcpServer(Map<String, dynamic> server) async {
    await _post('/api/mcp/servers', {...server, 'confirm': true});
  }

  Future<void> deleteMcpServer(String name) async {
    await _delete('/api/mcp/servers/${Uri.encodeComponent(name)}');
  }

  Future<Map<String, dynamic>> testMcpServer(String name) async {
    return await _post(
        '/api/mcp/servers/${Uri.encodeComponent(name)}/test');
  }

  Future<void> setMcpServerEnabled(String name, bool enabled) async {
    await _post(
        '/api/mcp/servers/${Uri.encodeComponent(name)}/${enabled ? 'enable' : 'disable'}');
  }

  Future<void> reloadMcp() async {
    await _post('/api/mcp/reload');
  }

  // ------------------------------------------------------------------
  // Plugins
  // ------------------------------------------------------------------

  Future<List<Plugin>> plugins() async {
    final j = await _get('/api/plugins');
    final list = (j['plugins'] as List?) ?? [];
    return list
        .whereType<Map>()
        .map((e) => Plugin.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<void> approvePlugin(String kind, String name) async {
    await _post(
        '/api/plugins/${Uri.encodeComponent(kind)}/${Uri.encodeComponent(name)}/approve');
  }

  Future<void> disablePlugin(String kind, String name) async {
    await _post(
        '/api/plugins/${Uri.encodeComponent(kind)}/${Uri.encodeComponent(name)}/disable');
  }

  // ------------------------------------------------------------------
  // Gateway
  // ------------------------------------------------------------------

  Future<void> restartGateway() async {
    await _post('/api/gateway/restart', {'confirm': true});
  }

  // ------------------------------------------------------------------
  // Schedule: full CRUD + trigger + templates
  // ------------------------------------------------------------------

  Future<ScheduledJob> createJob(Map<String, dynamic> body) async {
    return ScheduledJob.fromJson(await _post('/api/schedule/jobs', body));
  }

  Future<ScheduledJob> updateJob(String id, Map<String, dynamic> body) async {
    return ScheduledJob.fromJson(
        await _put('/api/schedule/jobs/${Uri.encodeComponent(id)}', body));
  }

  Future<void> deleteJob(String id) async {
    await _delete('/api/schedule/jobs/${Uri.encodeComponent(id)}');
  }

  Future<void> triggerJob(String id) async {
    await _post('/api/schedule/jobs/${Uri.encodeComponent(id)}/trigger');
  }

  Future<List<ScheduleTemplate>> scheduleTemplates() async {
    final j = await _get('/api/schedule/templates');
    final list = (j['templates'] as List?) ?? [];
    return list
        .whereType<Map>()
        .map((e) => ScheduleTemplate.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<void> createTemplate(Map<String, dynamic> body) async {
    await _post('/api/schedule/templates', body);
  }

  Future<void> deleteTemplate(String name) async {
    await _delete(
        '/api/schedule/templates/${Uri.encodeComponent(name)}');
  }
}
