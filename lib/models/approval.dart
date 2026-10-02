class Approval {
  final String id; // scope string, used as the decide path segment
  final String runId;
  final String? runTitle;
  final int runCreatedMs;
  final String? callId;
  final String? tool;
  final String? args;

  /// Grant tiers the backend offers for this approval, as the raw
  /// `available_tiers` strings (`once`/`session`/`always`). Empty when
  /// the field is absent (older backend) — callers must then render the
  /// plain Grant/Deny fallback.
  final List<String> availableTiers;

  Approval({
    required this.id,
    required this.runId,
    this.runTitle,
    required this.runCreatedMs,
    this.callId,
    this.tool,
    this.args,
    this.availableTiers = const [],
  });

  factory Approval.fromJson(Map<String, dynamic> j) => Approval(
        id: j['id'] as String? ?? '',
        runId: j['run_id'] as String? ?? '',
        runTitle: j['run_title'] as String?,
        runCreatedMs: (j['run_created_ms'] as num?)?.toInt() ?? 0,
        callId: j['call_id'] as String?,
        tool: j['tool'] as String?,
        args: j['args'] as String?,
        availableTiers: _parseTiers(j['available_tiers']),
      );

  /// Only tiers the backend actually offered survive; order is kept as
  /// the backend listed it, so callers can render exactly the offered
  /// subset and never invent a tier.
  static List<String> _parseTiers(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<String>()
        .where(_knownTiers.contains)
        .toList(growable: false);
  }

  static const _knownTiers = {'once', 'session', 'always'};

  String get displayRun =>
      (runTitle != null && runTitle!.isNotEmpty) ? runTitle! : runId;
}

/// One durable standing ("always") grant:
/// `GET /api/approvals/grants` → `{grants: [{id, tool, args_preview,
/// created_ms}]}`. Args leave the server only as a redacted preview,
/// never the raw string.
class StandingGrant {
  final int id;
  final String tool;
  final String argsPreview;
  final int createdMs;

  StandingGrant({
    required this.id,
    required this.tool,
    required this.argsPreview,
    required this.createdMs,
  });

  factory StandingGrant.fromJson(Map<String, dynamic> j) => StandingGrant(
        id: (j['id'] as num?)?.toInt() ?? 0,
        tool: j['tool'] as String? ?? '',
        argsPreview: j['args_preview'] as String? ?? '',
        createdMs: (j['created_ms'] as num?)?.toInt() ?? 0,
      );
}
