import 'pending_input.dart';

class TranscriptItem {
  final String type; // message | reasoning
  final String? role;
  final String content;
  /// Milliseconds since epoch when present. The dashboard does not emit
  /// per-message timestamps yet, so this is usually null; the app stamps
  /// its own optimistic messages.
  final int? tsMs;

  TranscriptItem(
      {required this.type, this.role, required this.content, this.tsMs});

  factory TranscriptItem.fromJson(Map<String, dynamic> j) => TranscriptItem(
        type: j['type'] as String? ?? 'message',
        role: j['role'] as String?,
        content: j['content'] as String? ?? '',
        tsMs: (j['ts_ms'] as num?)?.toInt(),
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
  final String? queuedMessage;
  final String mode; // plan | build
  final ContextTokens contextTokens;

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
    this.queuedMessage,
    this.mode = 'build',
    this.contextTokens = const ContextTokens(),
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
      queuedMessage: j['queued_message'] as String?,
      mode: j['mode'] as String? ?? 'build',
      contextTokens: ctx is Map
          ? ContextTokens.fromJson(ctx.cast<String, dynamic>())
          : const ContextTokens(),
    );
  }

  int get totalTokens => inputTokens + outputTokens;

  String get displayTitle =>
      title.isEmpty ? id.substring(0, id.length > 8 ? 8 : id.length) : title;
}
