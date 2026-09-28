class TranscriptItem {
  final String type; // message | reasoning
  final String? role;
  final String content;

  TranscriptItem({required this.type, this.role, required this.content});

  factory TranscriptItem.fromJson(Map<String, dynamic> j) => TranscriptItem(
        type: j['type'] as String? ?? 'message',
        role: j['role'] as String?,
        content: j['content'] as String? ?? '',
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
  final int? endedMs;
  final int turns;
  final int toolCalls;
  final int approvalsPending;
  final List<TranscriptItem> transcript;
  final List<TimelineItem> timeline;

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
    this.endedMs,
    required this.turns,
    required this.toolCalls,
    required this.approvalsPending,
    this.transcript = const [],
    this.timeline = const [],
  });

  factory PantheonRun.fromJson(Map<String, dynamic> j) {
    List<T> listOf<T>(dynamic v, T Function(Map<String, dynamic>) f) {
      if (v is! List) return [];
      return v
          .whereType<Map>()
          .map((e) => f(e.cast<String, dynamic>()))
          .toList();
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
      endedMs: (j['ended_ms'] as num?)?.toInt(),
      turns: (j['turns'] as num?)?.toInt() ?? 0,
      toolCalls: (j['tool_calls'] as num?)?.toInt() ?? 0,
      approvalsPending: (j['approvals_pending'] as num?)?.toInt() ?? 0,
      transcript: listOf(j['transcript'], TranscriptItem.fromJson),
      timeline: listOf(j['timeline'], TimelineItem.fromJson),
    );
  }

  int get totalTokens => inputTokens + outputTokens;

  String get displayTitle =>
      title.isEmpty ? id.substring(0, id.length > 8 ? 8 : id.length) : title;
}
