import 'package:flutter/material.dart';

import '../models/health.dart';
import '../services/pantheon_api.dart';
import '../theme.dart';
import '../widgets/pantheon_card.dart';
import '../widgets/states.dart';
import 'health_subsystem_screen.dart';

/// System health: status header, needs-attention issues, and the six
/// subsystems with drill-downs. Data comes from `GET /api/health`
/// (`PantheonApi.healthReport`), with a client-side fallback composed
/// from existing endpoints on older dashboards.
class HealthScreen extends StatefulWidget {
  final PantheonApi api;

  const HealthScreen({super.key, required this.api});

  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen> {
  Future<HealthReport>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _future = widget.api.healthReport();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Health'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded,
                color: P.inkSecondary, weight: 1.6),
            onPressed: _load,
          ),
        ],
      ),
      body: FutureBuilder<HealthReport>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(
                child: CircularProgressIndicator(color: P.accent));
          }
          if (snap.hasError) {
            return EmptyState(
              icon: Icons.monitor_heart_outlined,
              title: 'Couldn\'t load system health',
              body: snap.error.toString(),
              ctaLabel: 'Retry',
              onCta: _load,
            );
          }
          final report = snap.data!;
          return RefreshIndicator(
            onRefresh: () async => _load(),
            color: P.accent,
            backgroundColor: P.surface,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                _statusHeader(report),
                const SizedBox(height: 12),
                _statCards(report),
                if (report.issues.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text('Needs attention', style: PT.sectionTitle),
                  const SizedBox(height: 12),
                  for (final issue in report.issues) ...[
                    _issueCard(issue),
                    const SizedBox(height: 12),
                  ],
                ],
                const SizedBox(height: 24),
                Text('Subsystems', style: PT.sectionTitle),
                const SizedBox(height: 12),
                PRowCard(rows: [
                  for (final s in report.subsystems)
                    PRow(
                      title: s.title,
                      subtitle: s.subtitle.isEmpty ? null : s.subtitle,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(s.status.label,
                              style: PT.label
                                  .copyWith(color: s.status.color)),
                          const SizedBox(width: 4),
                          Icon(Icons.chevron_right_rounded,
                              size: 20, color: P.inkFaint),
                        ],
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) =>
                                HealthSubsystemScreen(subsystem: s)),
                      ),
                    ),
                ]),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _statusHeader(HealthReport report) {
    final overall = report.overall;
    final pillLabel = switch (overall) {
      HealthStatus.healthy => 'Operational',
      HealthStatus.review => 'Degraded',
      HealthStatus.down => 'Down',
      HealthStatus.unknown => 'Unknown',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
                child: Text('System status', style: PT.sectionTitle)),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: overall.color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(pillLabel,
                  style: PT.label
                      .copyWith(color: overall.color, fontSize: 13)),
            ),
          ],
        ),
        if (report.summary.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(report.summary,
              style: PT.small.copyWith(color: P.inkSecondary)),
        ],
      ],
    );
  }

  Widget _statCards(HealthReport report) {
    final core = report.coreRuntimeStatus;
    final coreIcon = switch (core) {
      HealthStatus.healthy => Icons.check_circle_rounded,
      HealthStatus.review => Icons.warning_rounded,
      HealthStatus.down => Icons.error_rounded,
      HealthStatus.unknown => Icons.help_outline_rounded,
    };
    final n = report.issueCount;
    final issuesColor =
        n == 0 ? P.ok : (report.issues.any((i) => i.severity == 'error')
            ? P.err
            : P.warn);
    return Row(
      children: [
        Expanded(
          child: PCard(
            color: P.tonal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('CORE RUNTIME', style: PT.overline),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(coreIcon, color: core.color, size: 22),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(report.coreRuntimeLabel,
                          style: PT.sectionTitle.copyWith(fontSize: 20)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: PCard(
            color: P.tonal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ISSUES', style: PT.overline),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                        n == 0
                            ? Icons.check_circle_rounded
                            : Icons.warning_amber_rounded,
                        color: issuesColor,
                        size: 22),
                    const SizedBox(width: 8),
                    Text(n == 0 ? 'None' : '$n found',
                        style: PT.sectionTitle.copyWith(fontSize: 20)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _issueCard(HealthIssue issue) {
    final icon = switch (issue.severity) {
      'error' => Icons.error_outline_rounded,
      'warning' => Icons.warning_amber_rounded,
      _ => Icons.info_outline_rounded,
    };
    final color = switch (issue.severity) {
      'error' => P.err,
      'warning' => P.warn,
      _ => P.info,
    };
    return PCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(issue.title, style: PT.cardTitle),
                if (issue.detail.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(issue.detail,
                      style: PT.small.copyWith(color: P.inkSecondary)),
                ],
                if (issue.hint.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(issue.hint,
                      style: PT.small.copyWith(color: P.ink)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
