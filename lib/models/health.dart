import 'package:flutter/material.dart';

import '../theme.dart';

/// Health data from `GET /api/health` (`pantheon.health/v1`).
///
/// Every `fromJson` here parses defensively: missing or mistyped fields
/// fall back to sensible defaults and never throw on partial data. A
/// check that could not actually run is `skipped`/`unknown` — the app
/// never reports a fake `healthy`.

/// Subsystem status. The `overall` field of the contract uses
/// `healthy|degraded|unhealthy|unknown`; [parse] folds `degraded` into
/// [review] and `unhealthy` into [down].
enum HealthStatus {
  healthy,
  review,
  down,
  unknown;

  String get label => switch (this) {
        healthy => 'Healthy',
        review => 'Review',
        down => 'Down',
        unknown => 'Unknown',
      };

  Color get color => switch (this) {
        healthy => P.ok,
        review => P.warn,
        down => P.err,
        unknown => P.inkFaint,
      };

  static HealthStatus parse(Object? value) =>
      switch (value?.toString().toLowerCase()) {
        'healthy' => healthy,
        'review' || 'degraded' => review,
        'down' || 'unhealthy' => down,
        _ => unknown,
      };
}

String _str(Map<String, dynamic> j, String key, [String dflt = '']) {
  final v = j[key];
  if (v is String) return v;
  if (v == null) return dflt;
  return v.toString();
}

int _int(Map<String, dynamic> j, String key, [int dflt = 0]) {
  final v = j[key];
  if (v is num) return v.toInt();
  return dflt;
}

List<Map<String, dynamic>> _mapList(Map<String, dynamic> j, String key) {
  final v = j[key];
  if (v is! List) return const [];
  return v.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
}

/// One diagnostic check. `status` is one of
/// `passed|failed|skipped|not_applicable`; `severity` is one of
/// `critical|error|warning|info`.
class HealthCheck {
  final String id;
  final String status;
  final String severity;
  final String summary;
  final String details;
  final String impact;
  final String remediation;
  final int durationNs;

  const HealthCheck({
    required this.id,
    required this.status,
    required this.severity,
    required this.summary,
    required this.details,
    required this.impact,
    required this.remediation,
    required this.durationNs,
  });

  bool get passed => status == 'passed';
  bool get failed => status == 'failed';
  bool get ran => status == 'passed' || status == 'failed';

  double get durationMs => durationNs / 1e6;

  factory HealthCheck.fromJson(Map<String, dynamic> j) => HealthCheck(
        id: _str(j, 'id'),
        status: _str(j, 'status', 'skipped').toLowerCase(),
        severity: _str(j, 'severity', 'info').toLowerCase(),
        summary: _str(j, 'summary'),
        details: _str(j, 'details'),
        impact: _str(j, 'impact'),
        remediation: _str(j, 'remediation'),
        durationNs: _int(j, 'duration_ns'),
      );
}

/// One subsystem: `runtime|providers|memory|tools|security|config`.
class SubsystemHealth {
  final String id;
  final String title;
  final String subtitle;
  final HealthStatus status;
  final List<HealthCheck> checks;

  const SubsystemHealth({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.checks,
  });

  factory SubsystemHealth.fromJson(Map<String, dynamic> j) =>
      SubsystemHealth(
        id: _str(j, 'id'),
        title: _str(j, 'title', _str(j, 'id')),
        subtitle: _str(j, 'subtitle'),
        status: HealthStatus.parse(j['status']),
        checks: _mapList(j, 'checks').map(HealthCheck.fromJson).toList(),
      );
}

/// One item needing attention. `severity` is `error|warning|info`.
class HealthIssue {
  final String id;
  final String subsystem;
  final String severity;
  final String title;
  final String detail;
  final String hint;

  const HealthIssue({
    required this.id,
    required this.subsystem,
    required this.severity,
    required this.title,
    required this.detail,
    required this.hint,
  });

  factory HealthIssue.fromJson(Map<String, dynamic> j) => HealthIssue(
        id: _str(j, 'id'),
        subsystem: _str(j, 'subsystem'),
        severity: _str(j, 'severity', 'info').toLowerCase(),
        title: _str(j, 'title'),
        detail: _str(j, 'detail'),
        hint: _str(j, 'hint'),
      );
}

/// The full health report.
class HealthReport {
  final String schema;
  final String generatedAt;
  final HealthStatus overall;
  final String summary;
  final HealthStatus coreRuntimeStatus;
  final String coreRuntimeLabel;
  final int issueCount;
  final List<SubsystemHealth> subsystems;
  final List<HealthIssue> issues;

  const HealthReport({
    required this.schema,
    required this.generatedAt,
    required this.overall,
    required this.summary,
    required this.coreRuntimeStatus,
    required this.coreRuntimeLabel,
    required this.issueCount,
    required this.subsystems,
    required this.issues,
  });

  factory HealthReport.fromJson(Map<String, dynamic> j) {
    final issues =
        _mapList(j, 'issues').map(HealthIssue.fromJson).toList();
    final core = j['core_runtime'] is Map
        ? (j['core_runtime'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};
    final coreStatus = HealthStatus.parse(core['status']);
    return HealthReport(
      schema: _str(j, 'schema', 'pantheon.health/v1'),
      generatedAt: _str(j, 'generated_at'),
      overall: HealthStatus.parse(j['overall']),
      summary: _str(j, 'summary'),
      coreRuntimeStatus: coreStatus,
      coreRuntimeLabel: _str(core, 'label', coreStatus.label),
      issueCount: j.containsKey('issue_count')
          ? _int(j, 'issue_count')
          : issues.length,
      subsystems:
          _mapList(j, 'subsystems').map(SubsystemHealth.fromJson).toList(),
      issues: issues,
    );
  }
}
