/// Nightly repair loop status from `GET /api/nightly/status`:
///
/// ```json
/// {
///   "enabled": true,
///   "reason": "explicit flag on",
///   "explicit": true,
///   "model_pin": false,
///   "next_run_ms": 1790449200000,
///   "last_run_ms": 0,
///   "last_summary": "..."
/// }
/// ```
class NightlyStatus {
  final bool enabled;
  final String reason;
  final bool? explicit;
  final bool modelPin;
  final int? nextRunMs;
  final int lastRunMs;
  final String lastSummary;

  NightlyStatus({
    required this.enabled,
    required this.reason,
    required this.explicit,
    required this.modelPin,
    required this.nextRunMs,
    required this.lastRunMs,
    required this.lastSummary,
  });

  factory NightlyStatus.fromJson(Map<String, dynamic> j) => NightlyStatus(
        enabled: j['enabled'] == true,
        reason: j['reason'] as String? ?? '',
        explicit: j['explicit'] as bool?,
        modelPin: j['model_pin'] == true,
        nextRunMs: (j['next_run_ms'] as num?)?.toInt(),
        lastRunMs: (j['last_run_ms'] as num?)?.toInt() ?? 0,
        lastSummary: j['last_summary'] as String? ?? '',
      );
}
