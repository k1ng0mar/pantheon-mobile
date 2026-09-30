import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/pantheon_api.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/chips.dart';
import '../widgets/expert_avatar.dart';
import '../widgets/forms.dart';
import '../widgets/pantheon_card.dart';
import '../widgets/states.dart';
import '../widgets/new_chat_sheet.dart';
import 'session_detail_screen.dart';

/// `POST /api/teams/:id/use` then push the spawned session with the
/// team shown as a removable chip above the composer. Returns true when
/// navigation happened. Shared by the Teams tab cards and the detail
/// screen's CTA.
Future<bool> useTeamAndOpenSession(
    BuildContext context, PantheonApi api, Team team) async {
  try {
    final sessionId = await api.useTeam(team.id);
    if (!context.mounted) return false;
    Navigator.of(context).push(
      buildDetailRoute(SessionDetailScreen(
        api: api,
        runId: sessionId,
        attachedName: team.name,
        attachedIcon: Icons.groups_outlined,
      )),
    );
    return true;
  } catch (e) {
    if (context.mounted) toastError(context, e);
    return false;
  }
}

/// Detail view for one expert team ("team of experts"): full
/// description, member roster with roles, task-brief preview, and the
/// "Use team" CTA.
class ExpertDetailScreen extends StatefulWidget {
  final PantheonApi api;
  final String teamId;

  /// The team as seen in the gallery: shown immediately while the
  /// detail fetch runs.
  final Team? seed;

  const ExpertDetailScreen({
    super.key,
    required this.api,
    required this.teamId,
    this.seed,
  });

  @override
  State<ExpertDetailScreen> createState() => _ExpertDetailScreenState();
}

class _ExpertDetailScreenState extends State<ExpertDetailScreen> {
  Team? _team;
  String? _error;
  bool _loading = true;
  bool _using = false;

  @override
  void initState() {
    super.initState();
    _team = widget.seed;
    _loading = widget.seed == null;
    _load();
  }

  Future<void> _load() async {
    try {
      final team = await widget.api.getTeam(widget.teamId);
      if (!mounted) return;
      setState(() {
        _team = team;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _use() async {
    final team = _team;
    if (team == null || _using) return;
    setState(() => _using = true);
    try {
      await useTeamAndOpenSession(context, widget.api, team);
    } finally {
      if (mounted) setState(() => _using = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final team = _team;
    return Scaffold(
      appBar: AppBar(
        title: Text(team?.name ?? 'Team'),
      ),
      body: _loading
          ? _skeleton()
          : team == null
              ? EmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: 'Couldn\'t load team',
                  body: _error ?? 'The team could not be loaded.',
                  ctaLabel: 'Retry',
                  onCta: _load,
                )
              : Column(
                  children: [
                    Expanded(child: _body(team)),
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding:
                            const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        child: GradientButton(
                          label: _using ? 'Starting…' : 'Use team',
                          onTap: _using ? null : _use,
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _skeleton() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: 5,
      itemBuilder: (_, __) => const Padding(
        padding: EdgeInsets.only(bottom: 10),
        child: Shimmer(width: double.infinity, height: 64, radius: 16),
      ),
    );
  }

  Widget _body(Team team) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        PCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  AvatarStack(
                    members: [
                      for (final m in team.members)
                        (name: m.name, colorHex: m.color),
                    ],
                    size: 44,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(team.name, style: PT.cardTitle),
                        const SizedBox(height: 2),
                        Text(
                          '${team.members.length} '
                          '${team.members.length == 1 ? 'member' : 'members'}',
                          style: PT.meta,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (team.description.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(team.description, style: PT.body),
              ],
            ],
          ),
        ),
        const Overline('Team roster'),
        for (var i = 0; i < team.members.length; i++)
          StaggerItem(index: i, child: _memberRow(team.members[i])),
        if (team.briefTemplate.isNotEmpty) ...[
          const Overline('Task brief'),
          PCard(
            child: Text(
              team.briefTemplate,
              style: PT.mono.copyWith(
                fontSize: 12.5,
                color: P.inkSecondary,
                height: 1.5,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _memberRow(TeamMember m) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PCard(
        child: Row(
          children: [
            MemberAvatar(name: m.name, colorHex: m.color, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(m.name, style: PT.rowTitle),
                  if (m.role.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(m.role, style: PT.meta),
                  ],
                ],
              ),
            ),
            if (m.profile.isNotEmpty)
              StatusChip(
                label: m.profile.toUpperCase(),
                color: P.inkFaint,
              ),
          ],
        ),
      ),
    );
  }
}
