class GatewayStatus {
  final String detected;
  final String? installed;
  final bool running;

  GatewayStatus(
      {required this.detected, this.installed, required this.running});

  factory GatewayStatus.fromJson(Map<String, dynamic> j) => GatewayStatus(
        detected: j['detected'] as String? ?? 'unknown',
        installed: j['installed'] as String?,
        running: j['running'] as bool? ?? false,
      );
}
