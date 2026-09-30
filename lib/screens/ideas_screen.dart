import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/pantheon_api.dart';
import '../theme.dart';
import '../widgets/forms.dart';
import '../widgets/new_chat_sheet.dart';
import '../widgets/states.dart';
import 'idea_detail_screen.dart';
import 'nightly_screen.dart';

/// Ideas proposed by the nightly pass: icon, bold title, dim
/// description per idea. Tapping opens the detail view; the three-dot
/// menu accepts, dismisses, or rates an idea.
class IdeasScreen extends StatefulWidget {
  final PantheonApi api;

  const IdeasScreen({super.key, required this.api});

  @override
  State<IdeasScreen> createState() => _IdeasScreenState();
}

class _IdeasScreenState extends State<IdeasScreen> {
  Future<List<Idea>>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() => _future = widget.api.ideas());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ideas'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded,
                color: P.inkSecondary, weight: 1.6),
            onPressed: _load,
          ),
        ],
      ),
      body: FutureBuilder<List<Idea>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return _skeleton();
          }
          if (snap.hasError) {
            return EmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'Couldn\'t load ideas',
              body: snap.error.toString(),
              ctaLabel: 'Retry',
              onCta: _load,
            );
          }
          final ideas = snap.data!;
          if (ideas.isEmpty) return _empty();
          return RefreshIndicator(
            onRefresh: () async => _load(),
            color: P.accent,
            backgroundColor: P.surface,
            child: _list(ideas),
          );
        },
      ),
    );
  }

  /// Pending first; accepted/dismissed sink below, dimmed.
  Widget _list(List<Idea> ideas) {
    final sorted = ideas.toList()
      ..sort((a, b) {
        final pa = a.isPending ? 0 : 1;
        final pb = b.isPending ? 0 : 1;
        if (pa != pb) return pa.compareTo(pb);
        return b.id.compareTo(a.id);
      });
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 24),
      itemCount: sorted.length,
      itemBuilder: (context, i) =>
          StaggerItem(index: i, child: _ideaRow(sorted[i])),
    );
  }

  Widget _ideaRow(Idea idea) {
    final handled = !idea.isPending;
    return InkWell(
      onTap: () => Navigator.of(context).push(
        buildDetailRoute(IdeaDetailScreen(
          api: widget.api,
          idea: idea,
          onChanged: _load,
        )),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: P.accentSoft,
                borderRadius: BorderRadius.circular(P.r14),
              ),
              child: Icon(
                idea.isScheduledTask
                    ? Icons.schedule_outlined
                    : Icons.lightbulb_outlined,
                color: handled ? P.inkFaint : P.accent,
                size: 22,
                weight: 1.6,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    idea.title,
                    style: PT.rowTitle.copyWith(
                      fontWeight: FontWeight.w700,
                      color: handled ? P.inkFaint : P.ink,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (idea.description.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      idea.description,
                      style: PT.meta.copyWith(color: P.inkMuted),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (handled) ...[
                    const SizedBox(height: 6),
                    _statusChip(idea.status),
                  ],
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.more_vert_rounded,
                  color: P.inkFaint, size: 20),
              tooltip: 'Idea actions',
              onPressed: () => showIdeaActions(context, widget.api, idea,
                  onChanged: _load),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(String status) {
    final accepted = status == 'accepted';
    final color = accepted ? P.ok : P.inkFaint;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        accepted ? 'Accepted' : 'Dismissed',
        style: PT.faint.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _empty() {
    return EmptyState(
      icon: Icons.lightbulb_outlined,
      title: 'No ideas yet',
      body: 'Ideas appear here after the nightly pass runs. '
          'If nightly repair is off, no ideas are generated.',
      ctaLabel: 'Nightly repair',
      onCta: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => NightlyScreen(api: widget.api))),
    );
  }

  Widget _skeleton() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: 5,
      itemBuilder: (_, __) => const Padding(
        padding: EdgeInsets.only(bottom: 10),
        child: Shimmer(width: double.infinity, height: 68, radius: 16),
      ),
    );
  }
}

/// The per-idea three-dot menu, as a Nyx action sheet:
/// accept ("Let's do it"), positive feedback ("More like this"), or
/// dismiss + negative feedback ("Not interested"). Shared by the list
/// and detail screens.
Future<void> showIdeaActions(
  BuildContext context,
  PantheonApi api,
  Idea idea, {
  VoidCallback? onChanged,
}) async {
  final action = await showPSheet<String>(
    context,
    SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SheetHandle(),
            const SizedBox(height: 8),
            Text(idea.title,
                style: PT.rowTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 12),
            _actionRow(Icons.check_rounded, 'Let\'s do it',
                () => Navigator.pop(context, 'accept')),
            _actionRow(Icons.thumb_up_outlined, 'More like this',
                () => Navigator.pop(context, 'more')),
            _actionRow(Icons.thumb_down_outlined, 'Not interested',
                () => Navigator.pop(context, 'less')),
          ],
        ),
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  try {
    switch (action) {
      case 'accept':
        await api.acceptIdea(idea.id);
        idea.status = 'accepted';
        onChanged?.call();
        if (context.mounted) {
          toast(context, 'Accepted. Pantheon will take it from here.');
        }
        break;
      case 'more':
        await api.feedbackIdea(idea.id, 'more');
        if (context.mounted) toast(context, 'Noted — more like this.');
        break;
      case 'less':
        await api.dismissIdea(idea.id);
        await api.feedbackIdea(idea.id, 'less');
        idea.status = 'dismissed';
        onChanged?.call();
        if (context.mounted) toast(context, 'Dismissed.');
        break;
    }
  } catch (e) {
    if (context.mounted) toastError(context, e);
  }
}

Widget _actionRow(IconData icon, String label, VoidCallback onTap) {
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(P.r12),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: P.ink),
          const SizedBox(width: 14),
          Text(label,
              style: PT.rowTitle.copyWith(fontSize: 15)),
        ],
      ),
    ),
  );
}
