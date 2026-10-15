/// Bot Screen desktop status (`GET /api/desktop/status` →).
/// Backend: `pantheon-dashboard/src/desktop.rs`. `controller` is null when
/// no human holds the takeover lease; `takenSince` is null unless taken.
class DesktopStatus {
  final bool enabled;
  final String driver;
  final String? controller;
  final int viewers;
  final DateTime? takenSince;

  DesktopStatus({
    required this.enabled,
    required this.driver,
    this.controller,
    required this.viewers,
    this.takenSince,
  });

  factory DesktopStatus.fromJson(Map<String, dynamic> j) {
    return DesktopStatus(
      enabled: j['enabled'] as bool? ?? false,
      driver: j['driver'] as String? ?? 'unknown',
      controller: j['controller'] as String?,
      viewers: (j['viewers'] as num?)?.toInt() ?? 0,
      takenSince: j['taken_since'] is String
          ? DateTime.tryParse(j['taken_since'] as String)
          : null,
    );
  }

  /// True when a human currently holds the takeover lease.
  bool get taken => controller != null && controller!.isNotEmpty;
}

/// Result of `POST /api/desktop/takeover`: the lease the client must
/// present on input/heartbeat/release.
class DesktopTakeover {
  final String leaseId;
  final int expiresIn;

  DesktopTakeover({required this.leaseId, required this.expiresIn});

  factory DesktopTakeover.fromJson(Map<String, dynamic> j) {
    return DesktopTakeover(
      leaseId: j['lease_id'] as String? ?? '',
      expiresIn: (j['expires_in'] as num?)?.toInt() ?? 0,
    );
  }
}
