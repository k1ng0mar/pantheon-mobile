/// Status of the browser tool backend (`GET /api/browser/status`).
class BrowserStatus {
  final bool enabled;
  final String backend;
  final String? note;

  BrowserStatus({required this.enabled, required this.backend, this.note});

  factory BrowserStatus.fromJson(Map<String, dynamic> j) => BrowserStatus(
        enabled: j['enabled'] as bool? ?? false,
        backend: j['backend'] as String? ?? 'unknown',
        note: j['note'] as String?,
      );
}
