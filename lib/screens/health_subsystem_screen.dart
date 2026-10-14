import 'package:flutter/material.dart';

import '../models/health.dart';
import '../theme.dart';
import '../widgets/pantheon_card.dart';

/// Drill-down for one subsystem: every diagnostic check with its status,
/// expandable details / impact / remediation.
class HealthSubsystemScreen extends StatelessWidget {
  final SubsystemHealth subsystem;

  const HealthSubsystemScreen({super.key, required this.subsystem});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(subsystem.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          if (subsystem.subtitle.isNotEmpty) ...[
            Text(subsystem.subtitle,
                style: PT.small.copyWith(color: P.inkSecondary)),
            const SizedBox(height: 12),
          ],
          for (final check in subsystem.checks) ...[
            _CheckTile(check: check),
            const SizedBox(height: 12),
          ],
          if (subsystem.checks.isEmpty)
            Text('No checks reported for this subsystem.',
                style: PT.small.copyWith(color: P.inkFaint)),
        ],
      ),
    );
  }
}

class _CheckTile extends StatefulWidget {
  final HealthCheck check;

  const _CheckTile({required this.check});

  @override
  State<_CheckTile> createState() => _CheckTileState();
}

class _CheckTileState extends State<_CheckTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.check;
    final (icon, color) = switch (c.status) {
      'passed' => (Icons.check_circle_rounded, P.ok),
      'failed' => switch (c.severity) {
          'critical' || 'error' => (Icons.error_rounded, P.err),
          _ => (Icons.warning_rounded, P.warn),
        },
      'not_applicable' => (Icons.info_outline_rounded, P.inkFaint),
      _ => (Icons.remove_circle_outline_rounded, P.inkFaint),
    };
    final hasMore = c.details.isNotEmpty ||
        c.impact.isNotEmpty ||
        c.remediation.isNotEmpty;
    return PCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: hasMore ? () => setState(() => _expanded = !_expanded) : null,
            borderRadius: BorderRadius.circular(P.r16),
            splashColor: P.accentSoft,
            highlightColor: P.accentSoft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.summary,
                          style: PT.rowTitle.copyWith(
                              color: c.ran ? P.ink : P.inkMuted)),
                      if (c.durationNs > 0) ...[
                        const SizedBox(height: 2),
                        Text(_formatDuration(c.durationNs), style: PT.meta),
                      ],
                    ],
                  ),
                ),
                if (hasMore)
                  Icon(
                      _expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: P.inkFaint,
                      size: 20),
              ],
            ),
          ),
          if (_expanded && hasMore) ...[
            const SizedBox(height: 12),
            if (c.details.isNotEmpty)
              _detailRow('Details', c.details),
            if (c.impact.isNotEmpty) ...[
              const SizedBox(height: 8),
              _detailRow('Impact', c.impact),
            ],
            if (c.remediation.isNotEmpty) ...[
              const SizedBox(height: 8),
              _detailRow('Remediation', c.remediation),
            ],
          ],
        ],
      ),
    );
  }

  Widget _detailRow(String label, String body) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: PT.overline.copyWith(fontSize: 10)),
        const SizedBox(height: 4),
        Text(body, style: PT.small.copyWith(color: P.inkSecondary)),
      ],
    );
  }

  String _formatDuration(int ns) {
    final ms = ns / 1e6;
    if (ms < 1000) return '${ms.toStringAsFixed(ms < 10 ? 1 : 0)} ms';
    return '${(ms / 1000).toStringAsFixed(2)} s';
  }
}
