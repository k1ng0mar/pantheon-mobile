import 'package:flutter/material.dart';

import '../models/pantheon_run.dart';
import '../services/pantheon_api.dart';
import '../theme.dart';
import '../widgets/chips.dart';
import '../widgets/states.dart';

class RunDetailScreen extends StatefulWidget {
  final PantheonApi api;
  final String runId;

  const RunDetailScreen({super.key, required this.api, required this.runId});

  @override
  State<RunDetailScreen> createState() => _RunDetailScreenState();
}

class _RunDetailScreenState extends State<RunDetailScreen> {
  Future<PantheonRun>? _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.runDetail(widget.runId);
  }

  Color _statusColor(String s) => switch (s) {
        'running' => P.live,
        'awaiting_approval' => P.warn,
        'completed' => P.ok,
        'failed' => P.err,
        _ => P.inkFaint,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.chevron_left_rounded,
              size: 30, color: P.ink, weight: 1.6),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Run'),
      ),
      body: FutureBuilder<PantheonRun>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return _skeleton();
          }
          if (snap.hasError) {
            return EmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'Couldn\'t load run',
              body: snap.error.toString(),
              ctaLabel: 'Retry',
              onCta: () =>
                  setState(() => _future = widget.api.runDetail(widget.runId)),
            );
          }
          final run = snap.data!;
          return DefaultTabController(
            length: 2,
            child: Column(
              children: [
                _header(run),
                TabBar(
                  tabs: const [Tab(text: 'Transcript'), Tab(text: 'Timeline')],
                  labelColor: P.ink,
                  unselectedLabelColor: P.inkMuted,
                  labelStyle: PT.label,
                  indicatorColor: P.accent,
                  indicatorWeight: 2.5,
                  dividerColor: P.divider,
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _transcript(run),
                      _timeline(run),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _header(PantheonRun run) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF2A0A7A), Color(0xFF150548)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(run.displayTitle,
                    style: PT.sectionTitle.copyWith(color: Colors.white)),
              ),
              const SizedBox(width: 8),
              StatusChip(
                label: run.status.replaceAll('_', ' ').toUpperCase(),
                color: _statusColor(run.status),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${timeAgo(run.createdMs)}${run.model != null ? ' · ${run.model}' : ''}${run.provider != null ? ' (${run.provider})' : ''}',
            style: PT.small.copyWith(color: const Color(0xFFB9AEE0)),
          ),
          const SizedBox(height: 14),
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
          Text(value,
              style: PT.label.copyWith(color: Colors.white, fontSize: 16)),
          Text(label, style: PT.faint.copyWith(color: const Color(0xFF8F82C4))),
        ],
      ),
    );
  }

  Widget _transcript(PantheonRun run) {
    if (run.transcript.isEmpty) {
      return const EmptyState(
        icon: Icons.chat_bubble_outline_rounded,
        title: 'No transcript yet',
        body: 'Messages will appear here once the run starts talking.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: run.transcript.length,
      itemBuilder: (context, i) {
        final t = run.transcript[i];
        return StaggerItem(index: i, child: _bubble(t));
      },
    );
  }

  Widget _bubble(TranscriptItem t) {
    if (t.type == 'reasoning') {
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: P.surface,
          borderRadius: BorderRadius.circular(P.r12),
          border: Border.all(color: P.border),
        ),
        child: Text(t.content,
            style: PT.small
                .copyWith(fontStyle: FontStyle.italic, color: P.inkMuted)),
      );
    }
    final isUser = t.role == 'user';
    final isTool = t.role == 'tool';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.85),
        decoration: BoxDecoration(
          gradient: isUser ? P.gradient : null,
          color: isUser
              ? null
              : isTool
                  ? P.tonal
                  : P.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(P.r18),
            topRight: const Radius.circular(P.r18),
            bottomLeft: Radius.circular(isUser ? P.r18 : P.r4),
            bottomRight: Radius.circular(isUser ? P.r4 : P.r18),
          ),
          border: isUser ? null : Border.all(color: P.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isUser)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text((t.role ?? 'assistant').toUpperCase(),
                    style: PT.monoEyebrow
                        .copyWith(color: isTool ? P.info : P.accent)),
              ),
            SelectableText(t.content,
                style: PT.body.copyWith(
                    fontSize: 14, color: isUser ? Colors.white : P.ink)),
          ],
        ),
      ),
    );
  }

  Widget _timeline(PantheonRun run) {
    if (run.timeline.isEmpty) {
      return const EmptyState(
        icon: Icons.timeline_rounded,
        title: 'No timeline events',
        body: 'Run events will stream in here.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 24),
      itemCount: run.timeline.length,
      itemBuilder: (context, i) {
        final e = run.timeline[i];
        final last = i == run.timeline.length - 1;
        return StaggerItem(
          index: i,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _kindColor(e.kind),
                      boxShadow: [
                        BoxShadow(
                          color: _kindColor(e.kind).withValues(alpha: 0.5),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                  if (!last) Container(width: 2, height: 30, color: P.border),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.kind.replaceAll('_', ' '),
                          style: PT.label.copyWith(fontSize: 13)),
                      if (e.detail != null && e.detail!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(e.detail!,
                              style: PT.meta,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(timeAgo(e.tsMs), style: PT.faint),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Color _kindColor(String kind) {
    if (kind.contains('failed') || kind.contains('denied')) return P.err;
    if (kind.contains('approval')) return P.warn;
    if (kind.contains('completed') || kind.contains('granted')) return P.ok;
    return P.accent;
  }

  Widget _skeleton() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        Shimmer(width: double.infinity, height: 120, radius: 16),
        SizedBox(height: 12),
        Shimmer(width: double.infinity, height: 80, radius: 14),
        SizedBox(height: 10),
        Shimmer(width: 240, height: 80, radius: 14),
      ],
    );
  }
}
