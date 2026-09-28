import 'package:flutter/material.dart';

import '../models/pantheon_run.dart';
import '../services/pantheon_api.dart';
import '../theme.dart';
import '../widgets/chips.dart';
import '../widgets/pantheon_card.dart';
import '../widgets/states.dart';
import 'run_detail_screen.dart';

class RunsScreen extends StatefulWidget {
  final PantheonApi api;

  const RunsScreen({super.key, required this.api});

  @override
  State<RunsScreen> createState() => _RunsScreenState();
}

class _RunsScreenState extends State<RunsScreen> {
  final _search = TextEditingController();
  String? _statusFilter;
  Future<List<PantheonRun>>? _future;

  static const _statuses = [
    'running',
    'awaiting_approval',
    'completed',
    'failed',
    'canceled',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _load() {
    setState(() {
      _future = widget.api.runs(
        q: _search.text.trim().isEmpty ? null : _search.text.trim(),
        status: _statusFilter,
      );
    });
  }

  Color _statusColor(String s) => switch (s) {
        'running' => P.live,
        'awaiting_approval' => P.warn,
        'completed' => P.ok,
        'failed' => P.err,
        _ => P.inkFaint,
      };

  String _statusLabel(String s) => s.replaceAll('_', ' ');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Runs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded,
                color: P.inkSecondary, weight: 1.6),
            onPressed: _load,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _load(),
              onChanged: (_) => setState(() {}),
              style: PT.body,
              decoration: InputDecoration(
                hintText: 'Search runs…',
                prefixIcon: const Icon(Icons.search_rounded,
                    color: P.inkFaint, weight: 1.6),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon:
                            const Icon(Icons.clear_rounded, color: P.inkFaint),
                        onPressed: () {
                          _search.clear();
                          _load();
                        },
                      ),
              ),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                _filterChip(null, 'all'),
                for (final s in _statuses) _filterChip(s, _statusLabel(s)),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<PantheonRun>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return _skeleton();
                }
                if (snap.hasError) {
                  return EmptyState(
                    icon: Icons.cloud_off_outlined,
                    title: 'Couldn\'t load runs',
                    body: snap.error.toString(),
                    ctaLabel: 'Retry',
                    onCta: _load,
                  );
                }
                final runs = snap.data!;
                if (runs.isEmpty) {
                  return const EmptyState(
                    icon: Icons.bolt_outlined,
                    title: 'No runs found',
                    body: 'Try a different search or status filter.',
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => _load(),
                  color: P.accent,
                  backgroundColor: P.surface,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: runs.length,
                    itemBuilder: (context, i) =>
                        StaggerItem(index: i, child: _runCard(runs[i])),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String? value, String label) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: PillChip(
        label: label,
        selected: _statusFilter == value,
        onTap: () {
          setState(() => _statusFilter = value);
          _load();
        },
      ),
    );
  }

  Widget _runCard(PantheonRun run) {
    final meta =
        '${timeAgo(run.createdMs)}${run.model != null ? ' · ${run.model}' : ''} · ${run.turns} turns · ${run.toolCalls} tools';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PCard(
        onTap: () => Navigator.of(context).push(_detailRoute(run)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (run.status == 'running')
                  const Padding(
                      padding: EdgeInsets.only(top: 6, right: 10),
                      child: LiveDot(size: 7))
                else
                  StatusDot(
                      color: _statusColor(run.status),
                      hollow: run.status == 'canceled'),
                if (run.status != 'running') const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    run.displayTitle,
                    style: PT.rowTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                StatusChip(
                    label: _statusLabel(run.status).toUpperCase(),
                    color: _statusColor(run.status)),
              ],
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 17),
              child: Text(
                '$meta · ${compactNum(run.totalTokens)} tok${run.costUsd > 0 ? ' · ${money(run.costUsd)}' : ''}',
                style: PT.meta,
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 17),
              child: Text(run.idPrefix, style: PT.monoEyebrow),
            ),
          ],
        ),
      ),
    );
  }

  Route _detailRoute(PantheonRun run) {
    return PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) =>
          RunDetailScreen(api: widget.api, runId: run.id),
      transitionsBuilder: (_, anim, __, child) {
        final slide = Tween<Offset>(
                begin: const Offset(0.08, 0), end: Offset.zero)
            .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic));
        final fade = Tween<double>(begin: 0, end: 1)
            .animate(CurvedAnimation(parent: anim, curve: Curves.easeOut));
        return SlideTransition(
            position: slide,
            child: FadeTransition(opacity: fade, child: child));
      },
    );
  }

  Widget _skeleton() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: 6,
      itemBuilder: (_, __) => const Padding(
        padding: EdgeInsets.only(bottom: 10),
        child: Shimmer(width: double.infinity, height: 96, radius: 16),
      ),
    );
  }
}

extension on PantheonRun {
  String get idPrefix => id.length > 12 ? '${id.substring(0, 12)}…' : id;
}
