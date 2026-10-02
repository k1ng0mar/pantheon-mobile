import 'pending_input.dart';

class ToolCallRef {
  final String id;
  final String name;
  final String arguments;

  /// Backend-provided wall-clock start of the tool call (ms since epoch).
  /// Absent on legacy rows.
  final int? startedMs;

  /// Backend-provided execution time in ms. Absent on legacy rows; the
  /// app falls back to the assistant→result timestamp delta.
  final int? durationMs;

  /// For a delegate call: the child run it spawned. Null for other
  /// calls and for delegations recorded before the link existed.
  final String? childRunId;

  ToolCallRef(
      {required this.id,
      required this.name,
      required this.arguments,
      this.startedMs,
      this.durationMs,
      this.childRunId});

  factory ToolCallRef.fromJson(Map<String, dynamic> j) => ToolCallRef(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        arguments: j['arguments'] as String? ?? '',
        startedMs: (j['started_ms'] as num?)?.toInt(),
        durationMs: (j['duration_ms'] as num?)?.toInt(),
        childRunId: j['child_run_id'] as String?,
      );
}

class TranscriptItem {
  final String type; // message | reasoning
  final String? role;
  final String content;
  /// Milliseconds since epoch when present. The dashboard emits
  /// per-message timestamps; older entries may omit them, in which case
  /// this is null and the app falls back to hiding the time.
  final int? tsMs;
  /// Tool invocations requested by an assistant message. The backend
  /// serializes these as `tool_calls: [{id, name, arguments}]` on the
  /// assistant row; the tool result rows follow with `role: "tool"` and
  /// a matching `tool_call_id`. Never empty except on legacy rows.
  final List<ToolCallRef> toolCalls;
  /// Present on `role: "tool"` rows; matches the assistant tool_call id.
  final String? toolCallId;

  /// Backend-provided execution time of a tool call, carried on the
  /// tool-result row. Absent on legacy rows.
  final int? durationMs;

  TranscriptItem(
      {required this.type,
      this.role,
      required this.content,
      this.tsMs,
      this.toolCalls = const [],
      this.toolCallId,
      this.durationMs});

  factory TranscriptItem.fromJson(Map<String, dynamic> j) => TranscriptItem(
        type: j['type'] as String? ?? 'message',
        role: j['role'] as String?,
        content: j['content'] as String? ?? '',
        tsMs: (j['ts_ms'] as num?)?.toInt(),
        toolCalls: ((j['tool_calls'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ToolCallRef.fromJson)
            .toList(),
        toolCallId: j['tool_call_id'] as String?,
        durationMs: (j['duration_ms'] as num?)?.toInt(),
      );
}

class TimelineItem {
  final int seq;
  final int tsMs;
  final String kind;
  final String? detail;

  TimelineItem(
      {required this.seq, required this.tsMs, required this.kind, this.detail});

  factory TimelineItem.fromJson(Map<String, dynamic> j) => TimelineItem(
        seq: (j['seq'] as num?)?.toInt() ?? 0,
        tsMs: (j['ts_ms'] as num?)?.toInt() ?? 0,
        kind: j['kind'] as String? ?? 'other',
        detail: j['detail'] as String?,
      );
}

/// Token usage snapshot from `context_tokens: {input, output, total}`.
class ContextTokens {
  final int input;
  final int output;
  final int total;

  const ContextTokens({this.input = 0, this.output = 0, this.total = 0});

  factory ContextTokens.fromJson(Map<String, dynamic> j) => ContextTokens(
        input: (j['input'] as num?)?.toInt() ?? 0,
        output: (j['output'] as num?)?.toInt() ?? 0,
        total: (j['total'] as num?)?.toInt() ??
            ((j['input'] as num?)?.toInt() ?? 0) +
                ((j['output'] as num?)?.toInt() ?? 0),
      );
}

class PantheonRun {
  final String id;
  final String status;
  final int createdMs;
  final String title;
  final String? model;
  final String? provider;
  final int inputTokens;
  final int outputTokens;
  final double costUsd;
  final int turns;
  final int toolCalls;
  final int approvalsPending;
  final int updatedMs;
  final String? lastActivity;
  final List<TranscriptItem> transcript;
  final List<TimelineItem> timeline;
  final List<PendingInput> pendingInput;
  /// FIFO list of follow-up messages parked while a turn runs, oldest
  /// first. Newer backends send a JSON array; older ones sent a single
  /// string or null (handled in [fromJson]).
  final List<String> queuedMessages;
  final String mode; // plan | build
  final ContextTokens contextTokens;

  /// The backend's permanent home session: carried on `is_home` (or a
  /// `pinned` flag). Falls back to matching id == 'home' when neither
  /// flag is present. The sessions list renders these above all others.
  final bool pinned;

  /// Whether the run is archived. Archived runs are excluded from the
  /// list endpoint unless `include_archived=1`.
  final bool archived;

  /// Project this run belongs to, if any (set via
  /// `POST /api/runs/:id/project`).
  final String? project;

  PantheonRun({
    required this.id,
    required this.status,
    required this.createdMs,
    required this.title,
    this.model,
    this.provider,
    required this.inputTokens,
    required this.outputTokens,
    required this.costUsd,
    required this.turns,
    required this.toolCalls,
    required this.approvalsPending,
    this.updatedMs = 0,
    this.lastActivity,
    this.transcript = const [],
    this.timeline = const [],
    this.pendingInput = const [],
    this.queuedMessages = const [],
    this.mode = 'build',
    this.contextTokens = const ContextTokens(),
    this.pinned = false,
    this.archived = false,
    this.project,
  });

  factory PantheonRun.fromJson(Map<String, dynamic> j) {
    List<T> listOf<T>(dynamic v, T Function(Map<String, dynamic>) f) {
      if (v is! List) return [];
      return v
          .whereType<Map>()
          .map((e) => f(e.cast<String, dynamic>()))
          .toList();
    }

    final ctx = j['context_tokens'];
    // Backend sends `pending_input` as a single object or null
    // (runs.rs:311-317); wrap the object so clarify cards render.
    final pi = j['pending_input'];
    final List<PendingInput> pendingInput;
    if (pi is Map) {
      pendingInput = [PendingInput.fromJson(pi.cast<String, dynamic>())];
    } else {
      pendingInput = listOf(pi, PendingInput.fromJson);
    }
    // `queued_message` is a FIFO list of message strings on newer
    // backends; older backends sent a single string or null.
    final qm = j['queued_message'];
    final List<String> queuedMessages;
    if (qm is List) {
      queuedMessages = qm.whereType<String>().toList();
    } else if (qm is String && qm.isNotEmpty) {
      queuedMessages = [qm];
    } else {
      queuedMessages = [];
    }
    return PantheonRun(
      id: j['id'] as String? ?? '',
      status: j['status'] as String? ?? 'unknown',
      createdMs: (j['created_ms'] as num?)?.toInt() ?? 0,
      title: j['title'] as String? ?? '',
      model: j['model'] as String?,
      provider: j['provider'] as String?,
      inputTokens: (j['input_tokens'] as num?)?.toInt() ?? 0,
      outputTokens: (j['output_tokens'] as num?)?.toInt() ?? 0,
      costUsd: (j['cost_usd'] as num?)?.toDouble() ?? 0,
      turns: (j['turns'] as num?)?.toInt() ?? 0,
      toolCalls: (j['tool_calls'] as num?)?.toInt() ?? 0,
      approvalsPending: (j['approvals_pending'] as num?)?.toInt() ?? 0,
      updatedMs: (j['updated_ms'] as num?)?.toInt() ?? 0,
      lastActivity: j['last_activity'] as String?,
      transcript: listOf(j['transcript'], TranscriptItem.fromJson),
      timeline: listOf(j['timeline'], TimelineItem.fromJson),
      pendingInput: pendingInput,
      queuedMessages: queuedMessages,
      mode: j['mode'] as String? ?? 'build',
      pinned: j['is_home'] == true ||
          j['pinned'] == true ||
          (j['id'] as String?) == 'home',
      archived: j['archived'] == true,
      project: j['project'] as String?,
      contextTokens: ctx is Map
          ? ContextTokens.fromJson(ctx.cast<String, dynamic>())
          : const ContextTokens(),
    );
  }

  int get totalTokens => inputTokens + outputTokens;

  String get displayTitle =>
      title.isEmpty ? id.substring(0, id.length > 8 ? 8 : id.length) : title;
}
