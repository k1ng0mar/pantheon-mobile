import 'dart:async';

import 'package:flutter/material.dart';

import '../services/pantheon_api.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/chips.dart';
import '../widgets/forms.dart';
import '../widgets/pantheon_card.dart';
import '../widgets/states.dart';
import '../widgets/profile_picture.dart';

/// Swarm coordination: split a task across N subagents (or hand-picked
/// profiles) and watch them work live while an optional judge rules on
/// the result. The last-viewed swarm id is kept in memory so navigating
/// away and back resumes polling where it left off.
class SwarmScreen extends StatefulWidget {
  final PantheonApi api;

  /// When set, the screen opens on this swarm's live view instead of the
  /// launcher (used by `/swarm <task>` after the launch call returns).
  final String? initialSwarmId;

  const SwarmScreen({super.key, required this.api, this.initialSwarmId});

  @override
  State<SwarmScreen> createState() => _SwarmScreenState();
}

class _SwarmView {
  final String swarmId;
  final String task;
  final String status;
  final int round;
  final List<_SwarmAgent> agents;
  final _SwarmVerdict? verdict;

  _SwarmView({
    required this.swarmId,
    required this.task,
    required this.status,
    required this.round,
    required this.agents,
    required this.verdict,
  });

  factory _SwarmView.fromJson(Map<String, dynamic> j) {
    final agents = (j['agents'] as List?)
            ?.whereType<Map>()
            .map((e) => _SwarmAgent.fromJson(e.cast<String, dynamic>()))
            .toList() ??
        [];
    final v = j['verdict'];
    return _SwarmView(
      swarmId: j['swarm_id']?.toString() ?? '',
      task: j['task']?.toString() ?? '',
      status: j['status']?.toString() ?? 'running',
      round: (j['round'] as num?)?.toInt() ?? 1,
      agents: agents,
      verdict: v is Map ? _SwarmVerdict.fromJson(v.cast<String, dynamic>()) : null,
    );
  }
}

class _SwarmAgent {
  final String name;
  final String profile;
  final String status;
  final String? summary;

  _SwarmAgent(
      {required this.name,
      required this.profile,
      required this.status,
      this.summary});

  factory _SwarmAgent.fromJson(Map<String, dynamic> j) => _SwarmAgent(
        name: j['name']?.toString() ?? '',
        profile: j['profile']?.toString() ?? '',
        status: j['status']?.toString() ?? 'waiting',
        summary: j['summary']?.toString(),
      );
}

class _SwarmVerdict {
  final bool done;
  final String notes;

  _SwarmVerdict({required this.done, required this.notes});

  factory _SwarmVerdict.fromJson(Map<String, dynamic> j) => _SwarmVerdict(
        done: j['done'] == true,
        notes: j['notes']?.toString() ?? '',
      );
}

class _SwarmScreenState extends State<SwarmScreen> {
  // Composer state.
  final _taskCtrl = TextEditingController();
  int _mode = 0; // 0 = N subagents, 1 = pick profiles
  int _count = 4;
  final Set<String> _selected = {};
  bool _judge = true;
  bool _launching = false;

  // Profiles for the picker (and agent avatars in the live view).
  List<({String name, String? avatar})> _profiles = [];
  bool _profilesLoading = true;
  String? _profilesError;

  // Live view state. [_swarmId] is kept in memory so navigating away
  // and back resumes the same swarm.
  String? _swarmId;
  _SwarmView? _status;
  bool _gone = false;
  bool _retrying = false;
  Timer? _poll;

  static const _pollInterval = Duration(seconds: 3);

  @override
  void initState() {
    super.initState();
    _loadProfiles();
    final seed = widget.initialSwarmId;
    if (seed != null && seed.isNotEmpty) {
      _swarmId = seed;
      _pollOnce();
      _ensurePolling();
    }
  }

  @override
  void dispose() {
    _taskCtrl.dispose();
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _loadProfiles() async {
    setState(() {
      _profilesLoading = true;
      _profilesError = null;
    });
    try {
      final doc = await widget.api.getConfig();
      if (!mounted) return;
      final list = doc.agents.entries
          .map((e) => (
                name: e.key,
                avatar: e.value['avatar'] as String?,
              ))
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      setState(() {
        _profiles = list;
        _profilesLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _profilesError = e.toString();
        _profilesLoading = false;
      });
    }
  }

  String? _avatarFor(String profile) {
    for (final p in _profiles) {
      if (p.name == profile) return p.avatar;
    }
    return null;
  }

  // ------------------------------------------------------------------
  // Polling
  // ------------------------------------------------------------------

  void _ensurePolling() {
    _poll ??= Timer.periodic(_pollInterval, (_) => _pollOnce());
  }

  void _stopPolling() {
    _poll?.cancel();
    _poll = null;
  }

  bool _isLive(String status) =>
      status == 'running' || status == 'judging';

  Future<void> _pollOnce() async {
    final id = _swarmId;
    if (id == null || !mounted) return;
    try {
      final j = await widget.api.swarmStatus(id);
      if (!mounted) return;
      final view = _SwarmView.fromJson(j);
      setState(() {
        _status = view;
        _gone = false;
      });
      if (!_isLive(view.status)) {
        _stopPolling();
      } else {
        _ensurePolling();
      }
    } on PantheonApiException catch (e) {
      // 404 = the swarm is gone (or the dashboard restarted): show the
      // empty state instead of retrying forever.
      if (e.status == 404 && mounted) {
        setState(() {
          _gone = true;
        });
        _stopPolling();
      }
      // Other errors are best-effort; the next tick retries.
    } catch (_) {
      // Best-effort; the next tick retries.
    }
  }

  // ------------------------------------------------------------------
  // Launch / retry
  // ------------------------------------------------------------------

  Future<void> _launch() async {
    final task = _taskCtrl.text.trim();
    if (task.isEmpty) {
      toastError(context, 'Give the swarm a task first.');
      return;
    }
    if (_mode == 1 && _selected.isEmpty) {
      toastError(context, 'Pick at least one profile.');
      return;
    }
    setState(() => _launching = true);
    try {
      final j = await widget.api.createSwarm(
        task: task,
        mode: _mode == 0 ? 'count' : 'profiles',
        subagentCount: _mode == 0 ? _count : null,
        profiles: _mode == 1 ? _selected.toList() : null,
        judge: _judge,
      );
      final id = j['swarm_id']?.toString();
      if (id == null || id.isEmpty) {
        throw PantheonApiException(500, 'Launch returned no swarm id.');
      }
      if (!mounted) return;
      setState(() {
        _swarmId = id;
        _status = null;
        _gone = false;
      });
      await _pollOnce();
      _ensurePolling();
    } catch (e) {
      if (mounted) toastError(context, e);
    } finally {
      if (mounted) setState(() => _launching = false);
    }
  }

  Future<void> _retry() async {
    final id = _swarmId;
    if (id == null) return;
    setState(() => _retrying = true);
    try {
      // The backend retry takes no feedback body (it relaunches with the
      // judge's notes), so send nothing: promising feedback would drop it.
      await widget.api.retrySwarm(id);
      if (!mounted) return;
      toast(context, 'Retry sent. Starting a new round.');
      _ensurePolling();
      await _pollOnce();
    } catch (e) {
      if (mounted) toastError(context, e);
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  void _newTask() {
    _stopPolling();
    setState(() {
      _swarmId = null;
      _status = null;
      _gone = false;
    });
  }

  Future<void> _openTranscript(_SwarmAgent agent) async {
    final id = _swarmId;
    if (id == null) return;
    await showPSheet(
      context,
      _TranscriptSheet(
        api: widget.api,
        swarmId: id,
        agent: agent,
        avatar: _avatarFor(agent.profile),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Build
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final live = _swarmId != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Swarm'),
        actions: [
          if (live)
            IconButton(
              icon: Icon(Icons.add_rounded,
                  color: P.inkSecondary, weight: 1.6),
              tooltip: 'New task',
              onPressed: _newTask,
            ),
          IconButton(
            icon: Icon(Icons.refresh_rounded,
                color: P.inkSecondary, weight: 1.6),
            onPressed: () => live ? _pollOnce() : _loadProfiles(),
          ),
        ],
      ),
      body: live ? _liveBody() : _composerBody(),
    );
  }

  // ------------------------------------------------------------------
  // Composer
  // ------------------------------------------------------------------

  Widget _composerBody() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        const Overline('New task'),
        PCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _taskCtrl,
                minLines: 3,
                maxLines: 5,
                style: PT.body,
                decoration: const InputDecoration(
                  hintText: 'What should the swarm do?',
                ),
              ),
              const SizedBox(height: 16),
              _segRow(),
              const SizedBox(height: 14),
              if (_mode == 0)
                Row(
                  children: [
                    Expanded(
                      child: Text('Subagents', style: PT.rowTitle),
                    ),
                    PStepper(
                      value: _count,
                      min: 1,
                      max: 8,
                      onChanged: (v) => setState(() => _count = v),
                    ),
                  ],
                )
              else
                _profilePicker(),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Judge', style: PT.rowTitle),
                        const SizedBox(height: 2),
                        Text(
                          'The judge rules on each round using the model pinned in [judge] under Models.',
                          style: PT.meta.copyWith(color: P.inkFaint),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _judge,
                    activeTrackColor: P.accent,
                    onChanged: (v) => setState(() => _judge = v),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GradientButton(
          label: _launching ? 'Launching…' : 'Launch swarm',
          onTap: _launching ? null : _launch,
        ),
      ],
    );
  }

  Widget _segRow() {
    return Row(
      children: [
        Expanded(
          child: SegTab(
            label: 'N subagents',
            selected: _mode == 0,
            onTap: () => setState(() => _mode = 0),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SegTab(
            label: 'Pick profiles',
            selected: _mode == 1,
            onTap: () => setState(() => _mode = 1),
          ),
        ),
      ],
    );
  }

  Widget _profilePicker() {
    if (_profilesLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Shimmer(width: double.infinity, height: 40, radius: 999),
      );
    }
    if (_profilesError != null) {
      return Row(
        children: [
          Expanded(
            child: Text('Couldn\'t load profiles: $_profilesError',
                style: PT.meta),
          ),
          IconButton(
            icon: Icon(Icons.refresh_rounded,
                color: P.inkSecondary, weight: 1.6),
            onPressed: _loadProfiles,
          ),
        ],
      );
    }
    if (_profiles.isEmpty) {
      return Text(
        'No profiles yet. Create one under More → Profiles first.',
        style: PT.meta.copyWith(color: P.inkFaint),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final p in _profiles) _profileChip(p.name, p.avatar),
      ],
    );
  }

  Widget _profileChip(String name, String? avatar) {
    final sel = _selected.contains(name);
    return GestureDetector(
      onTap: () => setState(
          () => sel ? _selected.remove(name) : _selected.add(name)),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.only(left: 6, top: 6, bottom: 6, right: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: sel ? P.accentSoft : Colors.transparent,
          border: Border.all(
              color: sel ? P.accent : P.borderStrong, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ProfilePicture(avatar: avatar, name: name, size: 26),
            const SizedBox(width: 8),
            Text(name,
                style: PT.label.copyWith(
                    fontSize: 13,
                    color: sel ? P.ink : P.inkSecondary)),
            if (sel) ...[
              const SizedBox(width: 4),
              Icon(Icons.check_rounded, size: 14, color: P.accent),
            ],
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Live view
  // ------------------------------------------------------------------

  Widget _liveBody() {
    if (_gone) {
      return EmptyState(
        icon: Icons.alt_route_outlined,
        title: 'Swarm not found',
        body: 'This swarm is gone — the dashboard may have restarted '
            'since it launched.',
        ctaLabel: 'New task',
        onCta: _newTask,
      );
    }
    final view = _status;
    if (view == null) {
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: 4,
        itemBuilder: (_, __) => const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: Shimmer(width: double.infinity, height: 72, radius: 16),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        if (view.verdict != null) _verdictBanner(view),
        PCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Round ${view.round}',
                        style: PT.cardTitle),
                  ),
                  _overallPill(view.status),
                ],
              ),
              const SizedBox(height: 6),
              Text(view.task,
                  style: PT.small,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < view.agents.length; i++)
          StaggerItem(
            index: i,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _agentCard(view.agents[i]),
            ),
          ),
      ],
    );
  }

  Widget _verdictBanner(_SwarmView view) {
    final verdict = view.verdict!;
    final color = verdict.done ? P.ok : P.warn;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(P.r16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                verdict.done
                    ? Icons.check_circle_rounded
                    : Icons.warning_amber_rounded,
                color: color,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                verdict.done ? 'Judge: complete' : 'Judge: not complete',
                style: PT.rowTitle.copyWith(color: color),
              ),
            ],
          ),
          if (verdict.notes.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(verdict.notes, style: PT.small),
          ],
          if (!verdict.done) ...[
            const SizedBox(height: 10),
            if (view.round >= 3)
              Text('Max rounds reached.',
                  style: PT.meta.copyWith(color: P.inkFaint))
            else
              // Plain retry: the backend ignores any feedback body, so the
              // button must not promise one. The next round is judged
              // again, and its notes drive the round after.
              PillButton(
                label: _retrying ? 'Retrying…' : 'Retry',
                color: P.warn,
                onTap: _retrying ? null : _retry,
              ),
          ],
        ],
      ),
    );
  }

  Widget _overallPill(String status) {
    return switch (status) {
      'complete' => const StatusChip(label: 'COMPLETE', color: P.ok),
      'incomplete' => const StatusChip(label: 'INCOMPLETE', color: P.err),
      'judging' => const StatusChip(label: 'JUDGING', color: P.warn),
      _ => const StatusChip(label: 'RUNNING', color: P.live),
    };
  }

  Widget _agentCard(_SwarmAgent agent) {
    return PCard(
      onTap: () => _openTranscript(agent),
      child: Row(
        children: [
          ProfilePicture(
              avatar: _avatarFor(agent.profile),
              name: agent.profile,
              size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(agent.name, style: PT.rowTitle),
                Text(agent.profile, style: PT.meta),
                if (agent.summary != null && agent.summary!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(agent.summary!,
                      style: PT.small,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          _agentPill(agent.status),
        ],
      ),
    );
  }

  /// Live status pill: pulsing accent dot while working, dim while
  /// waiting, green check when done, red when failed.
  Widget _agentPill(String status) {
    switch (status) {
      case 'working':
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LiveDot(),
            const SizedBox(width: 6),
            Text('Working',
                style: PT.monoEyebrow.copyWith(color: P.accent)),
          ],
        );
      case 'done':
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_rounded, size: 14, color: P.ok),
            const SizedBox(width: 6),
            Text('Done', style: PT.monoEyebrow.copyWith(color: P.ok)),
          ],
        );
      case 'failed':
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.close_rounded, size: 14, color: P.err),
            const SizedBox(width: 6),
            Text('Failed', style: PT.monoEyebrow.copyWith(color: P.err)),
          ],
        );
      default:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                  shape: BoxShape.circle, color: P.inkFaint),
            ),
            const SizedBox(width: 6),
            Text('Waiting',
                style: PT.monoEyebrow.copyWith(color: P.inkFaint)),
          ],
        );
    }
  }
}

/// Bottom sheet with one agent's live transcript: polls on the same
/// cadence as the parent view, readable mono text, auto-scrolls to the
/// bottom on new content while already near the bottom.
class _TranscriptSheet extends StatefulWidget {
  final PantheonApi api;
  final String swarmId;
  final _SwarmAgent agent;
  final String? avatar;

  const _TranscriptSheet({
    required this.api,
    required this.swarmId,
    required this.agent,
    this.avatar,
  });

  @override
  State<_TranscriptSheet> createState() => _TranscriptSheetState();
}

class _TranscriptSheetState extends State<_TranscriptSheet> {
  final _ctrl = ScrollController();
  bool _atBottom = true;
  Timer? _poll;
  String? _transcript;
  String _status = 'waiting';
  bool _loading = true;

  static const _pollInterval = Duration(seconds: 3);

  @override
  void initState() {
    super.initState();
    _status = widget.agent.status;
    _ctrl.addListener(_onScroll);
    _fetch();
    _poll = Timer.periodic(_pollInterval, (_) => _fetch());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_ctrl.hasClients) return;
    final pos = _ctrl.position;
    _atBottom = pos.maxScrollExtent - pos.pixels < 80;
  }

  Future<void> _fetch() async {
    if (!mounted) return;
    try {
      final j = await widget.api
          .swarmTranscript(widget.swarmId, widget.agent.name);
      if (!mounted) return;
      final t = j['transcript']?.toString() ?? '';
      final s = j['status']?.toString() ?? _status;
      final grew = t.length > (_transcript?.length ?? 0);
      setState(() {
        _transcript = t;
        _status = s;
        _loading = false;
      });
      if (grew && _atBottom) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_ctrl.hasClients) {
            _ctrl.jumpTo(_ctrl.position.maxScrollExtent);
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.75,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SheetHandle(),
              const SizedBox(height: 8),
              Row(
                children: [
                  ProfilePicture(
                      avatar: widget.avatar,
                      name: widget.agent.profile,
                      size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.agent.name, style: PT.rowTitle),
                        Text(widget.agent.profile, style: PT.meta),
                      ],
                    ),
                  ),
                  _statusLabel(_status),
                ],
              ),
              const SizedBox(height: 12),
              Divider(height: 1, thickness: 1, color: P.divider),
              const SizedBox(height: 12),
              Expanded(
                child: _loading && _transcript == null
                    ? Center(
                        child: CircularProgressIndicator(color: P.accent))
                    : (_transcript == null || _transcript!.isEmpty)
                        ? Text('No output yet.',
                            style: PT.meta.copyWith(color: P.inkFaint))
                        : SingleChildScrollView(
                            controller: _ctrl,
                            child: SelectableText(
                              _transcript!,
                              style: PT.mono.copyWith(
                                  fontSize: 12.5,
                                  color: P.ink,
                                  height: 1.5),
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusLabel(String status) {
    return switch (status) {
      'done' => const StatusChip(label: 'DONE', color: P.ok),
      'failed' => const StatusChip(label: 'FAILED', color: P.err),
      'working' => const StatusChip(label: 'WORKING', color: P.live),
      _ => StatusChip(label: 'WAITING', color: P.inkFaint),
    };
  }
}
