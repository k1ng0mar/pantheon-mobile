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
import 'expert_detail_screen.dart';
import 'session_detail_screen.dart';

/// Experts hub (More → Experts): two tabs matching the reference —
/// **Teams** (gallery of pre-built agent teams → team detail → use team)
/// and **Experts** (standalone experts → use expert). "Use" spawns a
/// session and opens it with a removable chip above the composer.
class ExpertsScreen extends StatelessWidget {
  final PantheonApi api;

  const ExpertsScreen({super.key, required this.api});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Experts'),
          bottom: TabBar(
            tabs: const [
              Tab(text: 'Teams'),
              Tab(text: 'Experts'),
            ],
            labelColor: P.ink,
            unselectedLabelColor: P.inkMuted,
            labelStyle: PT.label,
            indicatorColor: P.accent,
            indicatorWeight: 2.5,
            dividerColor: P.divider,
          ),
        ),
        body: TabBarView(
          children: [
            _TeamsTab(api: api),
            _ExpertsTab(api: api),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------
// Teams tab
// ------------------------------------------------------------------

class _TeamsTab extends StatefulWidget {
  final PantheonApi api;

  const _TeamsTab({required this.api});

  @override
  State<_TeamsTab> createState() => _TeamsTabState();
}

class _TeamsTabState extends State<_TeamsTab>
    with AutomaticKeepAlivesMixin {
  Future<List<Team>>? _future;
  final Set<String> _busy = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() => _future = widget.api.getTeams());
  }

  Future<void> _useTeam(Team team) async {
    if (_busy.contains(team.id)) return;
    setState(() => _busy.add(team.id));
    try {
      await useTeamAndOpenSession(context, widget.api, team);
    } finally {
      if (mounted) setState(() => _busy.remove(team.id));
    }
  }

  void _openDetail(Team team) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ExpertDetailScreen(
          api: widget.api,
          teamId: team.id,
          seed: team,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<List<Team>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return _skeleton();
        }
        if (snap.hasError) {
          return EmptyState(
            icon: Icons.cloud_off_outlined,
            title: 'Couldn\'t load teams',
            body: snap.error.toString(),
            ctaLabel: 'Retry',
            onCta: _load,
          );
        }
        final teams = snap.data!;
        if (teams.isEmpty) {
          return const EmptyState(
            icon: Icons.groups_outlined,
            title: 'No teams yet',
            body: 'Pre-built expert teams will appear here.',
          );
        }
        return RefreshIndicator(
          onRefresh: () async => _load(),
          color: P.accent,
          backgroundColor: P.surface,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              for (var i = 0; i < teams.length; i++)
                StaggerItem(
                  index: i,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _teamCard(teams[i]),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _skeleton() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: 4,
      itemBuilder: (_, __) => const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: Shimmer(width: double.infinity, height: 190, radius: 16),
      ),
    );
  }

  Widget _teamCard(Team team) {
    final busy = _busy.contains(team.id);
    return PCard(
      onTap: () => _openDetail(team),
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
              ),
              const Spacer(),
              StatusChip(
                label:
                    '${team.members.length} ${team.members.length == 1 ? 'MEMBER' : 'MEMBERS'}',
                color: P.inkFaint,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(team.name, style: PT.cardTitle),
          const SizedBox(height: 4),
          Text(
            team.description,
            style: PT.small,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  'View roster →',
                  style: PT.meta.copyWith(color: P.accent),
                ),
              ),
              PillButton(
                label: busy ? 'Starting…' : 'Use team',
                onTap: busy ? null : () => _useTeam(team),
                filled: false,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------
// Experts tab
// ------------------------------------------------------------------

/// `POST /api/experts/:id/use` then push the spawned session with the
/// expert shown as a removable chip above the composer. Returns true
/// when navigation happened.
Future<bool> useExpertAndOpenSession(
    BuildContext context, PantheonApi api, Expert expert) async {
  try {
    final sessionId = await api.useExpert(expert.id);
    if (!context.mounted) return false;
    Navigator.of(context).push(
      buildDetailRoute(SessionDetailScreen(
        api: api,
        runId: sessionId,
        attachedName: expert.name,
        attachedIcon: Icons.person_outline_rounded,
      )),
    );
    return true;
  } catch (e) {
    if (context.mounted) toastError(context, e);
    return false;
  }
}

class _ExpertsTab extends StatefulWidget {
  final PantheonApi api;

  const _ExpertsTab({required this.api});

  @override
  State<_ExpertsTab> createState() => _ExpertsTabState();
}

class _ExpertsTabState extends State<_ExpertsTab>
    with AutomaticKeepAlivesMixin {
  Future<List<Expert>>? _future;
  final Set<String> _busy = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() => _future = widget.api.getExperts());
  }

  Future<void> _useExpert(Expert expert) async {
    if (_busy.contains(expert.id)) return;
    setState(() => _busy.add(expert.id));
    try {
      await useExpertAndOpenSession(context, widget.api, expert);
    } finally {
      if (mounted) setState(() => _busy.remove(expert.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<List<Expert>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return _skeleton();
        }
        if (snap.hasError) {
          return EmptyState(
            icon: Icons.cloud_off_outlined,
            title: 'Couldn\'t load experts',
            body: snap.error.toString(),
            ctaLabel: 'Retry',
            onCta: _load,
          );
        }
        final experts = snap.data!;
        if (experts.isEmpty) {
          return const EmptyState(
            icon: Icons.person_outline_rounded,
            title: 'No experts yet',
            body: 'Standalone experts will appear here.',
          );
        }
        return RefreshIndicator(
          onRefresh: () async => _load(),
          color: P.accent,
          backgroundColor: P.surface,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              for (var i = 0; i < experts.length; i++)
                StaggerItem(
                  index: i,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _expertCard(experts[i]),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _skeleton() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: 5,
      itemBuilder: (_, __) => const Padding(
        padding: EdgeInsets.only(bottom: 10),
        child: Shimmer(width: double.infinity, height: 88, radius: 16),
      ),
    );
  }

  Widget _expertCard(Expert expert) {
    final busy = _busy.contains(expert.id);
    return PCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          MemberAvatar(
              name: expert.name, colorHex: expert.color, size: 52),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(expert.name, style: PT.rowTitle),
                const SizedBox(height: 3),
                Text(
                  expert.description,
                  style: PT.small,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          PillButton(
            label: busy ? 'Starting…' : 'Use expert',
            onTap: busy ? null : () => _useExpert(expert),
            filled: false,
          ),
        ],
      ),
    );
  }
}
