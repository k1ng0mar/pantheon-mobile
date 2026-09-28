class Overview {
  final int totalRuns;
  final Map<String, int> byStatus;
  final double cost24h;
  final int tokens24h;
  final int approvalsPending;
  final int jobsTotal;
  final int jobsActive;

  Overview({
    required this.totalRuns,
    required this.byStatus,
    required this.cost24h,
    required this.tokens24h,
    required this.approvalsPending,
    required this.jobsTotal,
    required this.jobsActive,
  });

  factory Overview.fromJson(Map<String, dynamic> j) {
    final runs = (j['runs'] as Map?)?.cast<String, dynamic>() ?? {};
    final day = (j['last_24h'] as Map?)?.cast<String, dynamic>() ?? {};
    final sched = (j['schedule'] as Map?)?.cast<String, dynamic>() ?? {};
    final status = (runs['by_status'] as Map?)?.cast<String, dynamic>() ?? {};
    return Overview(
      totalRuns: (runs['total'] as num?)?.toInt() ?? 0,
      byStatus: status.map((k, v) => MapEntry(k, (v as num).toInt())),
      cost24h: (day['cost_usd'] as num?)?.toDouble() ?? 0,
      tokens24h: (day['tokens'] as num?)?.toInt() ?? 0,
      approvalsPending: (j['approvals_pending'] as num?)?.toInt() ?? 0,
      jobsTotal: (sched['total'] as num?)?.toInt() ?? 0,
      jobsActive: (sched['active'] as num?)?.toInt() ?? 0,
    );
  }
}
