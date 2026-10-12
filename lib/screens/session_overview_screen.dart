import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/pantheon_api.dart';
import '../theme.dart';
import '../widgets/chips.dart';
import '../widgets/task_list.dart';
import '../widgets/team_run_view.dart';

/// Session details, reached from the conversation's actions menu.
///
/// Holds everything that used to compete with the chat for space on the
/// conversation screen: run metadata, execution stats (turns / tools /
/// tokens / cost), the Timeline task list, and the Team view for swarm
/// sessions. The conversation screen itself stays a pure chat.
class SessionOverviewScreen extends StatelessWidget {
  final PantheonApi api;
  final PantheonRun run;
  final String? swarmId;

  const SessionOverviewScreen({
    super.key,
    required this.api,
    required this.run,
    this.swarmId,
  });

  Color _statusColor(String status) {
    switch (status) {
      case 'running':
      case 'awaiting_approval':
        return P.live;
      case 'failed':
      case 'canceled':
        return P.err;
      case 'completed':
        return P.ok;
      default:
        return P.inkMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.chevron_left_rounded,
              size: 30, color: P.ink, weight: 1.6),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Session details'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _detailsCard(context),
          if (swarmId != null) _teamRow(context),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Overline('Timeline'),
          ),
          Expanded(child: SessionTaskList(run: run, api: api)),
        ],
      ),
    );
  }

  Widget _detailsCard(BuildContext context) {
    final modelLine = [
      if (run.provider != null && run.provider!.isNotEmpty) run.provider!,
      if (run.model != null && run.model!.isNotEmpty) run.model!,
    ].join(' · ');
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: P.surface,
        borderRadius: BorderRadius.circular(P.r16),
        border: Border.all(color: P.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(run.displayTitle,
              style: PT.cardTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          Row(
            children: [
              StatusChip(
                label: run.status.replaceAll('_', ' ').toUpperCase(),
                color: _statusColor(run.status),
              ),
              if (run.mode == 'plan') ...[
                const SizedBox(width: 8),
                StatusChip(label: 'PLAN', color: P.info),
              ],
              const Spacer(),
              Text(timeAgo(run.createdMs),
                  style: PT.small.copyWith(color: P.inkFaint)),
            ],
          ),
          if (modelLine.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(modelLine,
                style: PT.small.copyWith(color: P.inkSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              _stat('${run.turns}', 'turns'),
              _stat('${run.toolCalls}', 'tools'),
              _stat(compactNum(run.totalTokens), 'tokens'),
              _stat(money(run.costUsd), 'cost'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String value, String label) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: PT.label.copyWith(fontSize: 16)),
          Text(label, style: PT.faint.copyWith(color: P.inkFaint)),
        ],
      ),
    );
  }

  Widget _teamRow(BuildContext context) {
    final swarmId = this.swarmId;
    if (swarmId == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: OutlinedButton.icon(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => Scaffold(
              appBar: AppBar(
                leading: IconButton(
                  icon: Icon(Icons.chevron_left_rounded,
                      size: 30, color: P.ink, weight: 1.6),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                title: const Text('Team'),
              ),
              body: TeamRunView(api: api, swarmId: swarmId),
            ),
          ),
        ),
        icon: const Icon(Icons.groups_outlined, size: 18),
        label: const Text('Open team view'),
      ),
    );
  }
}
