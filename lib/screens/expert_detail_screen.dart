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
    final res = await api.useTeamFull(team.id);
    String? pick(List<String> keys) {
      for (final k in keys) {
        final v = res[k]?.toString();
        if (v != null && v.isNotEmpty) return v;
      }
      return null;
    }
    // run_id is the lead's coordination run — the user-facing session.
    final sessionId = pick(['run_id', 'swarm_id', 'session_id', 'id']);
    if (sessionId == null) {
      throw Exception('The /use endpoint returned no session id.');
    }
    if (!context.mounted) return false;
    Navigator.of(context).push(
      buildDetailRoute(SessionDetailScreen(
        api: api,
        runId: sessionId,
        attachedName: team.name,
        attachedIcon: Icons.groups_outlined,
        swarmId: res['swarm_id']?.toString(),
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
        if (team.topologyLabel.isNotEmpty || team.lead != null) ...[
          const Overline('How it runs'),
          PCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (team.topologyLabel.isNotEmpty)
                  StatusChip(
                      label: team.topologyLabel.toUpperCase(),
                      color: P.accent),
                if (team.lead != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      MemberAvatar(
                          name: team.lead!.name,
                          colorHex: team.lead!.color,
                          size: 36),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(team.lead!.name,
                                      style: PT.rowTitle
                                          .copyWith(fontSize: 13.5)),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                        color: P.accent
                                            .withValues(alpha: 0.5)),
                                  ),
                                  child: Text('LEAD',
                                      style: PT.label.copyWith(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w700,
                                        color: P.accent,
                                        letterSpacing: 0.8,
                                      )),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text('Only the lead talks to you.',
                                style: PT.meta),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
        if (team.stages.isNotEmpty) ...[
          const Overline('Stages'),
          for (var i = 0; i < team.stages.length; i++)
            StaggerItem(index: i, child: _stageCard(team, i)),
        ],
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

  Widget _stageCard(Team team, int i) {
    final s = team.stages[i];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: P.tonal,
                border: Border.all(color: P.border),
              ),
              child: Text(
                'Stage ${i + 1} · ${s.name}',
                style: PT.label.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: P.inkSecondary,
                ),
              ),
            ),
            if (s.members.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final id in s.members)
                    Builder(builder: (_) {
                      final m = team.memberByExpertId(id);
                      return Container(
                        padding: const EdgeInsets.fromLTRB(3, 3, 10, 3),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: P.border),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            MemberAvatar(
                              name: m?.name ?? id,
                              colorHex: m?.color ?? '',
                              size: 24,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              m?.name ?? id,
                              style: PT.label.copyWith(fontSize: 12),
                            ),
                            if (m != null && m.unresolved) ...[
                              const SizedBox(width: 4),
                              Icon(Icons.warning_amber_rounded,
                                  size: 13, color: P.warn),
                            ],
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ],
            if (s.inputContract.isNotEmpty) ...[
              const SizedBox(height: 8),
              _contractLine('in', s.inputContract),
            ],
            if (s.outputContract.isNotEmpty) ...[
              const SizedBox(height: 2),
              _contractLine('out', s.outputContract),
            ],
            if (s.loopBackTo != null && s.loopBackTo!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.loop_rounded, size: 14, color: P.inkMuted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'On verification failure loops back to ${s.loopBackTo}.',
                      style: PT.meta,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _contractLine(String kind, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 30,
          child: Text(kind.toUpperCase(),
              style: PT.label.copyWith(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: P.inkMuted,
                letterSpacing: 0.6,
              )),
        ),
        Expanded(
          child: Text(text,
              style: PT.body.copyWith(
                  fontSize: 12.5, height: 1.45, color: P.inkSecondary)),
        ),
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
                  if (m.unresolved) ...[
                    const SizedBox(height: 2),
                    Text('Expert deleted — unresolved.',
                        style: PT.meta.copyWith(color: P.warn)),
                  ] else if (m.role.isNotEmpty) ...[
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
