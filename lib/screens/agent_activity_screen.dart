import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/pantheon_api.dart';
import '../theme.dart';
import '../widgets/active_profile_avatar.dart';
import '../widgets/session_timeline.dart';
import '../widgets/states.dart';

/// Session-scoped agent activity: tap the agent avatar in chat and this
/// shows the agent's profile header (avatar, display name, live status,
/// provider · model, compact stats) above this session's activity
/// transcript.
///
/// Unlike Muse's day-grouped profile feed, this is scoped to one
/// session only. The status line is derived purely from the run's real
/// state — never invented.
class AgentActivityScreen extends StatefulWidget {
  final PantheonRun run;
  final PantheonApi api;

  const AgentActivityScreen({super.key, required this.run, required this.api});

  @override
  State<AgentActivityScreen> createState() => _AgentActivityScreenState();
}

class _AgentActivityScreenState extends State<AgentActivityScreen> {
  String? _agentName;

  @override
  void initState() {
    super.initState();
    _resolveAgentName();
  }

  Future<void> _resolveAgentName() async {
    try {
      final doc = await widget.api.getConfig();
      if (!mounted) return;
      setState(() => _agentName = doc.activeAgent);
    } catch (_) {
      // Falls back to the generic label below.
    }
  }

  /// Honest run-state status line. A live run shows the backend's last
  /// reported activity (or "Working"); settled runs get a plain status.
  String _statusLine(PantheonRun run) {
    final activity = (run.lastActivity ?? '').trim();
    switch (run.status) {
      case 'running':
        return activity.isNotEmpty ? activity : 'Working';
      case 'awaiting_approval':
        return 'Waiting for your approval';
      case 'failed':
        return 'Run failed';
      case 'canceled':
        return 'Run canceled';
      case 'completed':
        return 'Run completed';
      default:
        final s = run.status.replaceAll('_', ' ').trim();
        if (s.isEmpty) return 'Unknown';
        return s[0].toUpperCase() + s.substring(1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final run = widget.run;
    final badge = tlStatusBadge(run.status);
    final name = (_agentName ?? '').trim();
    final modelLine = [
      if (run.provider != null && run.provider!.isNotEmpty) run.provider!,
      if (run.model != null && run.model!.isNotEmpty) run.model!,
    ].join(' · ');
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.chevron_left_rounded,
              size: 30, color: P.ink, weight: 1.6),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Agent activity'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ActiveProfileAvatar(api: widget.api, size: 72),
            const SizedBox(height: 12),
            Text(
              name.isNotEmpty ? name : 'Pantheon agent',
              style: PT.sectionTitle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: badge.color,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    _statusLine(run),
                    style: PT.body
                        .copyWith(fontSize: 14.5, color: P.inkSecondary),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
            if (modelLine.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(modelLine, style: PT.meta, textAlign: TextAlign.center),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                _stat('${run.turns}', 'turns'),
                _stat('${run.toolCalls}', 'tools'),
                _stat(compactNum(run.totalTokens), 'tokens'),
              ],
            ),
            const SizedBox(height: 20),
            if (run.timeline.isEmpty)
              const EmptyState(
                icon: Icons.timeline_rounded,
                title: 'No activity yet',
                body: 'Run events will stream in here.',
              )
            else
              SessionTimeline(run: run),
          ],
        ),
      ),
    );
  }

  Widget _stat(String value, String label) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(value, style: PT.label.copyWith(fontSize: 16)),
          const SizedBox(height: 2),
          Text(label, style: PT.faint),
        ],
      ),
    );
  }
}
