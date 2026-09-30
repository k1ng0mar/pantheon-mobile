import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/models.dart';

/// Thrown when a message is sent while a turn is already running
/// (HTTP 409 with error code TURN_IN_FLIGHT). The caller can offer to
/// queue or steer instead.
class PantheonTurnInFlightException extends PantheonApiException {
  PantheonTurnInFlightException(String body) : super(409, body);
  @override
  String toString() => 'A turn is already running in this session.';
}

/// Thrown when a run can't be retried because it's parked on an
/// approval (HTTP 409 with error code RUN_PARKED).
class PantheonRetryParkedException extends PantheonApiException {
  PantheonRetryParkedException(String body) : super(409, body);
  @override
  String toString() => 'Parked on approval — grant or deny it first.';
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

/// A 404 from an endpoint the app knows but the dashboard doesn't:
/// the server is older than the app.
class PantheonStaleBackendException extends PantheonApiException {
  PantheonStaleBackendException(super.status, super.body);
  @override
  String toString() =>
      'This needs a newer dashboard — update Pantheon and try again.';
}

class PantheonUnreachableException implements Exception {
  final String message;
  PantheonUnreachableException(this.message);
  @override
  String toString() => message;
}

/// How `POST /api/runs/:id/message` resolved.
enum MessageSendOutcome {
  /// The message started (or joined) a turn immediately.
  sent,

  /// A turn was in flight; the message was parked in the FIFO queue.
  queued,

  /// The running turn was redirected and the message queued behind it.
  steered,
}

class MessageSendResult {
  final MessageSendOutcome outcome;
  MessageSendResult(this.outcome);

  bool get sent => outcome == MessageSendOutcome.sent;
  bool get queued => outcome == MessageSendOutcome.queued;
  bool get steered => outcome == MessageSendOutcome.steered;
}

/// HTTP client for the Pantheon dashboard API
/// (`pantheon dashboard --bind 0.0.0.0 --port 7171`).
class PantheonApi {
  PantheonApi({required this.baseUrl, required this.token});

  final String baseUrl;
  final String token;

  /// Fired after every successful `PUT /api/config`, so widgets showing
  /// profile-dependent state (avatars, active names) can re-resolve
  /// without a restart. Static so a PUT through one api instance
  /// notifies listeners holding any other instance.
  static final _configChanged = StreamController<void>.broadcast();

  /// Stream of config-change notifications (see [_configChanged]).
  static Stream<void> get configChanged => _configChanged.stream;

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
    return _decode(res, path);
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
    return _decode(res, path);
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
    return _decode(res, path);
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
    return _decode(res, path);
  }

  Future<Map<String, dynamic>> _patch(String path,
      [Map<String, dynamic>? body]) async {
    http.Response res;
    try {
      res = await http
          .patch(_uri(path),
              headers: {..._headers, 'Content-Type': 'application/json'},
              body: jsonEncode(body ?? {}))
          .timeout(_timeout);
    } on TimeoutException {
      throw PantheonUnreachableException('Timed out reaching $baseUrl.');
    } catch (e) {
      throw PantheonUnreachableException('Cannot reach $baseUrl ($e).');
    }
    return _decode(res, path);
  }

  /// Raw-bytes GET for download endpoints (config export, run export).
  Future<List<int>> _getBytes(String path,
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
    if (res.statusCode == 401) throw PantheonAuthException();
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw PantheonApiException(res.statusCode, _serverMessage(res.body));
    }
    return res.bodyBytes;
  }

  Map<String, dynamic> _decode(http.Response res, String path) {
    if (res.statusCode == 401) throw PantheonAuthException();
    if (res.statusCode == 404 && _isNewEndpoint(path)) {
      throw PantheonStaleBackendException(
          res.statusCode, _serverMessage(res.body));
    }
    if (res.statusCode == 409) {
      final msg = _serverMessage(res.body);
      switch (_serverCode(res.body)) {
        case 'TURN_IN_FLIGHT':
          throw PantheonTurnInFlightException(msg);
        case 'RUN_PARKED':
          throw PantheonRetryParkedException(msg);
        default:
          throw PantheonApiException(res.statusCode, msg);
      }
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw PantheonApiException(res.statusCode, _serverMessage(res.body));
    }
    final v = jsonDecode(res.body);
    return v is Map ? v.cast<String, dynamic>() : {'value': v};
  }

  /// Endpoints added after the app's first release: a 404 from one of
  /// these almost always means the dashboard is older than the app, not
  /// that the resource is missing.
  static bool _isNewEndpoint(String path) {
    return path.contains('/api/link-preview') ||
        path.contains('/api/browser/') ||
        path.contains('/api/logins') ||
        path.contains('/api/plugins/import') ||
        path.contains('/retry') ||
        path.contains('/kill') ||
        RegExp(r'/api/runs/[^/]+/queue/\d+').hasMatch(path);
  }

  /// The dashboard wraps errors as {"ok": false, "error": {"code": "…",
  /// "message": "…"}} — extract the machine code for typed 409 handling.
  static String? _serverCode(String body) {
    try {
      final v = jsonDecode(body);
      if (v is Map) {
        final err = v['error'];
        if (err is Map && err['code'] is String) {
          return err['code'] as String;
        }
      }
    } catch (_) {}
    return null;
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
    return list.whereType<Map>().map((e) {
      final envelope = e.cast<String, dynamic>();
      final job = envelope['job'];
      if (job is Map) {
        // Envelope: {"job": {...}, "last_run": ms|null,
        // "next_fire_ms": ms|null} (schedule.rs:68-84).
        return ScheduledJob.fromJson(
            Map<String, dynamic>.of(job.cast<String, dynamic>())
              ..['last_run'] = envelope['last_run']
              ..['next_fire_ms'] = envelope['next_fire_ms']);
      }
      // Flat job object (older backends).
      return ScheduledJob.fromJson(envelope);
    }).toList();
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

  /// Send a follow-up message into a run.
  ///
  /// - 200 → [MessageSendOutcome.sent]: the turn was admitted.
  /// - 202 with `queued: true` → [MessageSendOutcome.queued]: a turn was
  ///   in flight and the message was parked in the FIFO queue.
  /// - 202 with `steered: true` → [MessageSendOutcome.steered]: the
  ///   running turn was redirected and the message queued behind it.
  /// - 409 TURN_IN_FLIGHT → [PantheonTurnInFlightException] when neither
  ///   `queue` nor `steer` was requested.
  Future<MessageSendResult> sendRunMessage(String runId, String message,
      {bool queue = false, bool steer = false, List<String> attachments = const []}) async {
    final body = <String, dynamic>{'message': message};
    if (queue) body['queue'] = true;
    if (steer) body['steer'] = true;
    if (attachments.isNotEmpty) body['attachments'] = attachments;
    final j = await _post(
        '/api/runs/${Uri.encodeComponent(runId)}/message', body);
    if (j['steered'] == true) {
      return MessageSendResult(MessageSendOutcome.steered);
    }
    if (j['queued'] == true) {
      return MessageSendResult(MessageSendOutcome.queued);
    }
    return MessageSendResult(MessageSendOutcome.sent);
  }

  /// Cooperatively interrupt the running turn, if any.
  Future<void> cancelRun(String id) async {
    await _post('/api/runs/${Uri.encodeComponent(id)}/cancel');
  }

  /// Hard-stop the running turn: force-terminates the turn process
  /// (TERM, a short grace, then KILL). Unlike [cancelRun], the turn
  /// does not wind down cooperatively. 409 when no turn is in flight.
  Future<void> killRun(String id) async {
    await _post('/api/runs/${Uri.encodeComponent(id)}/kill');
  }

  /// Drop the queued follow-up message, if any.
  Future<void> clearQueue(String id) async {
    await _delete('/api/runs/${Uri.encodeComponent(id)}/queue');
  }

  /// Drop one queued message by its FIFO index.
  Future<void> deleteQueueItem(String id, int index) async {
    await _delete('/api/runs/${Uri.encodeComponent(id)}/queue/$index');
  }

  /// Replace the text of one queued message by its FIFO index.
  Future<void> editQueueItem(String id, int index, String text) async {
    await _patch(
        '/api/runs/${Uri.encodeComponent(id)}/queue/$index', {'text': text});
  }

  /// Retry a failed turn: the server replays the last user message as a
  /// new turn. Throws [PantheonTurnInFlightException] when a turn is
  /// already running, [PantheonRetryParkedException] when the run is
  /// parked on an approval.
  Future<void> retryRun(String id) async {
    await _post('/api/runs/${Uri.encodeComponent(id)}/retry');
  }

  /// Answer a parked `ask_user` question and resume the turn.
  Future<void> answerInput(
      String id, String callId, String answer) async {
    await _post('/api/runs/${Uri.encodeComponent(id)}/input',
        {'call_id': callId, 'answer': answer});
  }

  /// Rename a session.
  Future<void> renameRun(String id, String title) async {
    await _put('/api/runs/${Uri.encodeComponent(id)}/title',
        {'title': title});
  }

  /// Switch the session's agent mode ("plan" | "build"). Returns the
  /// effective mode.
  Future<String> setRunMode(String id, String mode) async {
    final j = await _post('/api/runs/${Uri.encodeComponent(id)}/mode',
        {'mode': mode});
    return j['mode'] as String? ?? mode;
  }

  /// Compress the session's context now. Returns a human summary built
  /// from the backend's {"before","after","changed","unknown_window"}
  /// report (runs.rs:737-743).
  Future<String> compressRun(String id) async {
    final j = await _post('/api/runs/${Uri.encodeComponent(id)}/compress');
    final before = (j['before'] as num?)?.toInt();
    final after = (j['after'] as num?)?.toInt();
    if (before == null) return 'Context compressed.';
    if (j['unknown_window'] == true) {
      return 'Context compressed (model window unknown).';
    }
    if (j['changed'] != true) {
      return 'Context already fits — no compression needed.';
    }
    if (after != null && before > 0 && after <= before) {
      final pct = (100 * (before - after) / before).round();
      return 'Context compressed: $before → $after tokens ($pct% smaller).';
    }
    return 'Context compressed.';
  }

  /// Fork the run at user turn [turn] (1-based; null = latest) into a
  /// brand-new run. Returns the new run's detail.
  Future<PantheonRun> forkRun(String id, {int? turn}) async {
    final body = <String, dynamic>{};
    if (turn != null) body['turn'] = turn;
    final j =
        await _post('/api/runs/${Uri.encodeComponent(id)}/fork', body);
    final newId = j['run_id'] as String?;
    if (newId == null || newId.isEmpty) {
      throw PantheonApiException(500, 'Fork returned no run_id.');
    }
    return runDetail(newId);
  }

  /// Download the session transcript as markdown bytes.
  Future<List<int>> exportRun(String id) => _getBytes(
      '/api/runs/${Uri.encodeComponent(id)}/export', {'format': 'markdown'});

  /// Delete a run from the ledger.
  Future<void> deleteRun(String id) async {
    await _delete('/api/runs/${Uri.encodeComponent(id)}');
  }

  // ------------------------------------------------------------------
  // Session todos
  // ------------------------------------------------------------------

  Future<List<TodoItem>> getTodos(String id) async {
    final j = await _get('/api/runs/${Uri.encodeComponent(id)}/todos');
    final list = (j['todos'] as List?) ?? [];
    return list
        .whereType<Map>()
        .map((e) => TodoItem.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<void> saveTodos(String id, List<TodoItem> todos) async {
    await _put('/api/runs/${Uri.encodeComponent(id)}/todos',
        {'todos': todos.map((t) => t.toJson()).toList()});
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
    if (j['key'] is String) {
      // Backend returns the flat entry (201, memory.rs:171-184).
      return MemoryEntry.fromJson(j);
    }
    return MemoryEntry(
        key: text.length > 40 ? '${text.substring(0, 40)}…' : text,
        value: text);
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
    _configChanged.add(null);
    return changed.map((e) => e.toString()).toList();
  }

  Future<void> importConfig(String toml) async {
    await _post('/api/config/import', {'toml': toml, 'confirm': true});
  }

  /// Persona files for an agent profile: SOUL.md / USER.md / AGENTS.md
  /// contents. Returns `{soul: {path, content}, user: {...}, agents: {...}}`;
  /// a missing file reports `{path: null, content: ""}`.
  Future<Map<String, dynamic>> profileFiles(String name) async {
    final j = await _get('/api/profiles/${Uri.encodeComponent(name)}/files');
    return j.cast<String, dynamic>();
  }

  /// Write one persona file for an agent profile. `file` is one of
  /// `soul`, `user`, `agents`. Creates the file under the profile's
  /// directory when the profile declares no path for it.
  Future<void> saveProfileFile(
      String name, String file, String content) async {
    await _put('/api/profiles/${Uri.encodeComponent(name)}/files',
        {'file': file, 'content': content});
  }

  /// Delete an agent profile and its settings. The backend answers 409
  /// when the profile is currently active.
  Future<void> deleteProfile(String name) async {
    await _delete('/api/profiles/${Uri.encodeComponent(name)}');
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
  // Website logins
  // ------------------------------------------------------------------

  /// `GET /api/logins` → masked entries. Passwords are never returned.
  Future<List<LoginEntry>> listLogins() async {
    final j = await _get('/api/logins');
    final list = (j['logins'] as List?) ?? [];
    return list
        .whereType<Map>()
        .map((e) => LoginEntry.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  /// `POST /api/logins` with `{site, username, password, confirm}`.
  Future<LoginEntry> createLogin(
      String site, String username, String password) async {
    final j = await _post('/api/logins', {
      'site': site,
      'username': username,
      'password': password,
      'confirm': true,
    });
    final entry = j['login'];
    if (entry is Map) {
      return LoginEntry.fromJson(entry.cast<String, dynamic>());
    }
    // Fall back to a refresh if the shape is unexpected.
    final all = await listLogins();
    return all.firstWhere((e) => e.site == site && e.username == username,
        orElse: () => LoginEntry(id: '', site: site, username: username));
  }

  /// `PUT /api/logins/:id` with any of `{site, username, password}`.
  /// The password key is only sent when it changed.
  Future<void> updateLogin(String id,
      {String? site, String? username, String? password}) async {
    final body = <String, dynamic>{'confirm': true};
    if (site != null) body['site'] = site;
    if (username != null) body['username'] = username;
    if (password != null && password.isNotEmpty) body['password'] = password;
    await _put('/api/logins/${Uri.encodeComponent(id)}', body);
  }

  /// `DELETE /api/logins/:id`.
  Future<void> deleteLogin(String id) async {
    await _delete('/api/logins/${Uri.encodeComponent(id)}');
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

  /// Approve a server stuck in `pending_approval`. The backend requires
  /// an explicit confirmation.
  Future<void> approveMcpServer(String name) async {
    await _post('/api/mcp/servers/${Uri.encodeComponent(name)}/approve',
        {'confirm': true});
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

  /// `POST /api/plugins/import` — `{url, ref?}` →
  /// `{name, kind, version, detected_capabilities, approval_required: true}`.
  /// Imported plugins land UNAPPROVED; the user must approve before loading.
  /// A 404 (endpoint not landed yet) surfaces as PantheonStaleBackendException
  /// via [_isNewEndpoint].
  Future<Map<String, dynamic>> importPlugin(
      {required String url, String? ref}) async {
    final body = <String, dynamic>{'url': url};
    final r = ref?.trim();
    if (r != null && r.isNotEmpty) body['ref'] = r;
    return await _post('/api/plugins/import', body);
  }

  // ------------------------------------------------------------------
  // Gateway
  // ------------------------------------------------------------------

  Future<void> restartGateway() async {
    await _post('/api/gateway/restart', {'confirm': true});
  }

  // ------------------------------------------------------------------
  // Nightly repair loop
  // ------------------------------------------------------------------

  /// `GET /api/nightly/status` — enable state, reason, next/last run.
  Future<NightlyStatus> nightlyStatus() async =>
      NightlyStatus.fromJson(await _get('/api/nightly/status'));

  /// `POST /api/nightly/enabled` — `{enabled, confirm: true}`. Returns
  /// the fresh status document.
  Future<NightlyStatus> setNightlyEnabled(bool enabled) async =>
      NightlyStatus.fromJson(await _post(
          '/api/nightly/enabled', {'enabled': enabled, 'confirm': true}));

  // ------------------------------------------------------------------
  // Ideas (proposed by the nightly pass)
  // ------------------------------------------------------------------

  /// `GET /api/ideas` → the idea list.
  Future<List<Idea>> ideas() async {
    final j = await _get('/api/ideas');
    final list = (j['ideas'] as List?) ?? [];
    return list
        .whereType<Map>()
        .map((e) => Idea.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  /// `POST /api/ideas/:id/accept` — the user wants this done.
  Future<void> acceptIdea(String id) async {
    await _post('/api/ideas/${Uri.encodeComponent(id)}/accept');
  }

  /// `POST /api/ideas/:id/dismiss` — the user isn't interested.
  Future<void> dismissIdea(String id) async {
    await _post('/api/ideas/${Uri.encodeComponent(id)}/dismiss');
  }

  /// `POST /api/ideas/:id/feedback` — `{"signal":"more"|"less"}`.
  Future<void> feedbackIdea(String id, String signal) async {
    await _post('/api/ideas/${Uri.encodeComponent(id)}/feedback',
        {'signal': signal});
  }

  // ------------------------------------------------------------------
  // Uploads (chat attachments)
  // ------------------------------------------------------------------

  /// `POST /api/uploads` — `{name, mime, data: base64}` → the stored
  /// upload record. The returned id rides `sendRunMessage` as an
  /// attachment so the agent can read the file.
  ///
  /// Pass a dedicated [client] to make the upload abortable: closing it
  /// fails the in-flight request with [http.ClientException].
  Future<UploadRecord> uploadAttachment({
    required String name,
    required String mime,
    required List<int> bytes,
    http.Client? client,
  }) async {
    final body = {
      'name': name,
      'mime': mime,
      'data': base64Encode(bytes),
    };
    if (client == null) {
      return UploadRecord.fromJson(await _post('/api/uploads', body));
    }
    http.Response res;
    try {
      res = await client
          .post(_uri('/api/uploads'),
              headers: {..._headers, 'Content-Type': 'application/json'},
              body: jsonEncode(body))
          .timeout(_timeout);
    } on TimeoutException {
      throw PantheonUnreachableException('Timed out reaching $baseUrl.');
    } on http.ClientException {
      rethrow;
    } catch (e) {
      throw PantheonUnreachableException('Cannot reach $baseUrl ($e).');
    }
    return UploadRecord.fromJson(_decode(res, '/api/uploads'));
  }

  /// `GET /api/uploads/:id` — raw bytes of a stored upload, for
  /// attachment thumbnails and opening sent files.
  Future<List<int>> downloadUpload(String id) =>
      _getBytes('/api/uploads/${Uri.encodeComponent(id)}');

  // ------------------------------------------------------------------
  // Link previews
  // ------------------------------------------------------------------

  /// `GET /api/link-preview?url=` — Open Graph / title / image metadata
  /// for a URL (SSRF-guarded server-side). Returns null when the page
  /// has nothing usable or the lookup fails; never throws, so chat
  /// rendering stays robust.
  Future<LinkPreview?> fetchLinkPreview(String url) async {
    try {
      final j = await _get('/api/link-preview', {'url': url});
      final preview = LinkPreview.fromJson(j);
      return preview.usable ? preview : null;
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------------
  // Voice notes
  // ------------------------------------------------------------------

  /// `POST /agui/voice/transcribe` — base64 audio → transcript text.
  /// Throws [PantheonApiException] carrying the server's message on
  /// failure (unconfigured STT, backend error, audio too large).
  Future<String> transcribeAudio(List<int> bytes) async {
    final j = await _post('/agui/voice/transcribe', {
      'audio': base64Encode(bytes),
    });
    final t = j['transcript'];
    if (t is! String || t.trim().isEmpty) {
      throw PantheonApiException(502, 'Transcription came back empty.');
    }
    return t;
  }

  // ------------------------------------------------------------------
  // Schedule: full CRUD + trigger + templates
  // ------------------------------------------------------------------

  /// Create returns an envelope `{ok, job, last_run, next_fire_ms}`:
  /// unwrap `job` and fold the envelope timing into it.
  Future<ScheduledJob> createJob(Map<String, dynamic> body) async {
    return _jobFromEnvelope(await _post('/api/schedule/jobs', body));
  }

  Future<ScheduledJob> updateJob(String id, Map<String, dynamic> body) async {
    return _jobFromEnvelope(
        await _put('/api/schedule/jobs/${Uri.encodeComponent(id)}', body));
  }

  ScheduledJob _jobFromEnvelope(Map<String, dynamic> j) {
    final raw = j['job'];
    final jobJson = raw is Map
        ? Map<String, dynamic>.from(raw.cast<String, dynamic>())
        : <String, dynamic>{};
    jobJson.putIfAbsent('last_run', () => j['last_run']);
    jobJson.putIfAbsent('next_fire_ms', () => j['next_fire_ms']);
    return ScheduledJob.fromJson(jobJson);
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

  /// Browser tool backend status (`GET /api/browser/status`). When
  /// `session` is given, `last_activity` narrates that session's latest
  /// browser action (agent tool call or take-control gesture).
  Future<BrowserStatus> browserStatus({String? session}) async {
    final q = session == null || session.isEmpty
        ? ''
        : '?session=${Uri.encodeQueryComponent(session)}';
    final j = await _get('/api/browser/status$q');
    return BrowserStatus.fromJson(j);
  }

  /// Forward an input action to a browser session
  /// (`POST /api/browser/input`). `action` is one of `tap` ({x, y}),
  /// `type` ({text}), `scroll` ({dx, dy}), `press` ({key}), `navigate`
  /// ({url}), `back`, `forward`, `reload`; `session` is optional.
  Future<void> browserInput(Map<String, dynamic> body) async {
    await _post('/api/browser/input', body);
  }

  // ------------------------------------------------------------------
  // Swarm: split a task across N subagents or picked profiles, with an
  // optional judge ruling whether the work is done.
  // ------------------------------------------------------------------

  /// `POST /api/swarm` → 201 `{"swarm_id","run_id","agents":[...]}`.
  /// 400 on bad input. [mode] is `"count"` or `"profiles"`.
  Future<Map<String, dynamic>> createSwarm({
    required String task,
    required String mode,
    int? subagentCount,
    List<String>? profiles,
    required bool judge,
  }) async {
    final body = <String, dynamic>{'task': task, 'mode': mode, 'judge': judge};
    if (subagentCount != null) body['subagent_count'] = subagentCount;
    if (profiles != null) body['profiles'] = profiles;
    return await _post('/api/swarm', body);
  }

  /// `GET /api/swarm/status?swarm=<id>` → task, status, round, per-agent
  /// statuses, and the judge verdict (null until judged).
  /// 404 when the swarm is unknown.
  Future<Map<String, dynamic>> swarmStatus(String id) async {
    return await _get('/api/swarm/status', {'swarm': id});
  }

  /// `GET /api/swarm/transcript?swarm=<id>&agent=<name>` → the agent's
  /// live transcript. 404 when the swarm or agent is unknown.
  Future<Map<String, dynamic>> swarmTranscript(String id, String agent) async {
    return await _get(
        '/api/swarm/transcript', {'swarm': id, 'agent': agent});
  }

  /// `GET /api/swarm/transcript?swarm=<id>` (no agent) → the combined
  /// transcript: every agent's output headed by name, run id, status,
  /// and role, plus the staged execution log for team runs.
  Future<Map<String, dynamic>> swarmCombinedTranscript(String id) async {
    return await _get('/api/swarm/transcript', {'swarm': id});
  }

  /// `POST /api/swarm/<id>/retry` → 200 `{"swarm_id","round"}`.
  /// No feedback → the backend defaults to the judge's notes.
  /// 400 when the max round is reached or there is nothing to retry.
  Future<Map<String, dynamic>> retrySwarm(String id,
      {String? feedback}) async {
    final body = <String, dynamic>{};
    if (feedback != null && feedback.isNotEmpty) body['feedback'] = feedback;
    return await _post(
        '/api/swarm/${Uri.encodeComponent(id)}/retry', body);
  }

  // ------------------------------------------------------------------
  // Expert teams & experts: pre-built teams of agents (and standalone
  // experts) whose `use` endpoints spawn a working session.
  // ------------------------------------------------------------------

  /// `GET /api/teams` → `{"teams": [...]}` (a bare list is accepted too).
  /// The teams `use` endpoint lives on the dashboard worker; the app
  /// codes defensively until its exact shape lands.
  Future<List<Team>> getTeams() async {
    final j = await _get('/api/teams');
    final list = (j['teams'] as List?) ?? [];
    return list
        .whereType<Map>()
        .map((e) => Team.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  /// `GET /api/teams/:id` → one team with its member roster.
  Future<Team> getTeam(String id) async {
    final j = await _get('/api/teams/${Uri.encodeComponent(id)}');
    return Team.fromJson(j);
  }

  /// `POST /api/teams/:id/use` with `{}` or `{"task": "..."}` →
  /// `{"ok": true, "swarm_id": ...}`. Spawns the swarm session and
  /// returns its id.
  Future<String> useTeam(String id, {String? task}) async {
    final j = await useTeamFull(id, task: task);
    return _sessionIdOf(j);
  }

  /// Full `POST /api/teams/:id/use` response: `swarm_id` plus `run_id`
  /// (the lead's coordination run — the single user-facing run).
  Future<Map<String, dynamic>> useTeamFull(String id, {String? task}) async {
    final body = <String, dynamic>{};
    if (task != null && task.isNotEmpty) body['task'] = task;
    return await _post('/api/teams/${Uri.encodeComponent(id)}/use', body);
  }

  /// `GET /api/experts` → `{"experts": [...]}` (a bare list accepted too).
  Future<List<Expert>> getExperts() async {
    final j = await _get('/api/experts');
    final list = (j['experts'] as List?) ?? [];
    return list
        .whereType<Map>()
        .map((e) => Expert.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  /// `POST /api/experts/:id/use` → `{"ok": true, ...}`. Spawns the
  /// expert's session and returns the new session id.
  Future<String> useExpert(String id) async {
    final j = await _post('/api/experts/${Uri.encodeComponent(id)}/use', {});
    return _sessionIdOf(j);
  }

  /// Read the spawned session id defensively: the contract says
  /// `swarm_id` (fallback `id`); `run_id` / `session_id` are accepted
  /// too in case the sibling backend varies the key.
  String _sessionIdOf(Map<String, dynamic> j) {
    for (final k in ['run_id', 'swarm_id', 'session_id', 'id']) {
      final v = j[k]?.toString();
      if (v != null && v.isNotEmpty) return v;
    }
    throw PantheonApiException(500, 'Use returned no session id.');
  }
}
