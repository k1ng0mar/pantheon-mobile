/// Latest browser narration for a session (`GET /api/browser/status` →
/// `last_activity`): what the agent or take-control last did, or null
/// when nothing was recorded yet.
class BrowserActivity {
  final String action;
  final String detail;
  final DateTime? at;

  BrowserActivity({required this.action, required this.detail, this.at});

  factory BrowserActivity.fromJson(Map<String, dynamic> j) => BrowserActivity(
        action: j['action'] as String? ?? '',
        detail: j['detail'] as String? ?? '',
        at: j['at'] is String ? DateTime.tryParse(j['at'] as String) : null,
      );
}

/// Status of the browser tool backend (`GET /api/browser/status`).
class BrowserStatus {
  final bool enabled;
  final String backend;
  final String? note;
  final BrowserActivity? lastActivity;

  BrowserStatus(
      {required this.enabled,
      required this.backend,
      this.note,
      this.lastActivity});

  factory BrowserStatus.fromJson(Map<String, dynamic> j) {
    final la = j['last_activity'];
    return BrowserStatus(
      enabled: j['enabled'] as bool? ?? false,
      backend: j['backend'] as String? ?? 'unknown',
      note: j['note'] as String?,
      lastActivity:
          la is Map<String, dynamic> ? BrowserActivity.fromJson(la) : null,
    );
  }
}
