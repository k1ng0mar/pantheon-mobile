class Approval {
  final String id; // scope string, used as the decide path segment
  final String runId;
  final String? runTitle;
  final int runCreatedMs;
  final String? callId;
  final String? tool;
  final String? args;

  Approval({
    required this.id,
    required this.runId,
    this.runTitle,
    required this.runCreatedMs,
    this.callId,
    this.tool,
    this.args,
  });

  factory Approval.fromJson(Map<String, dynamic> j) => Approval(
        id: j['id'] as String? ?? '',
        runId: j['run_id'] as String? ?? '',
        runTitle: j['run_title'] as String?,
        runCreatedMs: (j['run_created_ms'] as num?)?.toInt() ?? 0,
        callId: j['call_id'] as String?,
        tool: j['tool'] as String?,
        args: j['args'] as String?,
      );

  String get displayRun =>
      (runTitle != null && runTitle!.isNotEmpty) ? runTitle! : runId;
}
