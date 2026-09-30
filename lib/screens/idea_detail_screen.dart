import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/pantheon_api.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/forms.dart';
import '../widgets/pantheon_card.dart';
import 'ideas_screen.dart';

/// One idea: full title + description, a "What's included" card with
/// the plan steps, the schedule for scheduled-task ideas, and a
/// prominent "Let's do it" button.
class IdeaDetailScreen extends StatefulWidget {
  final PantheonApi api;
  final Idea idea;

  /// Called after accept/dismiss so the list refreshes behind.
  final VoidCallback? onChanged;

  const IdeaDetailScreen(
      {super.key, required this.api, required this.idea, this.onChanged});

  @override
  State<IdeaDetailScreen> createState() => _IdeaDetailScreenState();
}

class _IdeaDetailScreenState extends State<IdeaDetailScreen> {
  bool _accepting = false;

  Idea get _idea => widget.idea;

  Future<void> _accept() async {
    if (_accepting || !_idea.isPending) return;
    setState(() => _accepting = true);
    try {
      await widget.api.acceptIdea(_idea.id);
      _idea.status = 'accepted';
      widget.onChanged?.call();
      if (mounted) {
        toast(context, 'Accepted. Pantheon will take it from here.');
      }
    } catch (e) {
      if (mounted) toastError(context, e);
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final idea = _idea;
    return Scaffold(
      appBar: AppBar(
        title: Text(idea.kindLabel),
        actions: [
          IconButton(
            icon: Icon(Icons.more_vert_rounded, color: P.inkSecondary),
            tooltip: 'Idea actions',
            onPressed: () => showIdeaActions(context, widget.api, idea,
                onChanged: () {
              widget.onChanged?.call();
              if (mounted) setState(() {});
            }),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: P.accentSoft,
                  borderRadius: BorderRadius.circular(P.r14),
                ),
                child: Icon(
                  idea.isScheduledTask
                      ? Icons.schedule_outlined
                      : Icons.lightbulb_outlined,
                  color: P.accent,
                  size: 26,
                  weight: 1.6,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(idea.kindLabel,
                        style: PT.overline.copyWith(color: P.accent)),
                    if (idea.createdDay != null) ...[
                      const SizedBox(height: 2),
                      Text(idea.createdDay!, style: PT.meta),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(idea.title, style: PT.sectionTitle),
          if (idea.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(idea.description, style: PT.body),
          ],
          if (idea.includes.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text("What's included".toUpperCase(), style: PT.overline),
            const SizedBox(height: 8),
            PCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < idea.includes.length; i++) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: P.accentSoft,
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Text('${i + 1}',
                                style: PT.monoSm.copyWith(
                                    color: P.accent,
                                    fontWeight: FontWeight.w600)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Text(idea.includes[i], style: PT.small),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (i < idea.includes.length - 1)
                      const Divider(
                          height: 1, thickness: 1, indent: 14, endIndent: 14),
                  ],
                ],
              ),
            ),
          ],
          if (idea.isScheduledTask && idea.schedule != null) ...[
            const SizedBox(height: 20),
            Text('Schedule'.toUpperCase(), style: PT.overline),
            const SizedBox(height: 8),
            PCard(
              child: Column(
                children: [
                  for (final e in idea.schedule!.entries)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: KvRow(
                          e.key, e.value?.toString() ?? '—',
                          mono: true),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          _cta(idea),
        ],
      ),
    );
  }

  Widget _cta(Idea idea) {
    if (idea.isPending) {
      return GradientButton(
        label: _accepting ? 'Accepting…' : 'Let\'s do it',
        onTap: _accepting ? null : _accept,
      );
    }
    final accepted = idea.status == 'accepted';
    return PCard(
      borderColor:
          (accepted ? P.ok : P.inkFaint).withValues(alpha: 0.35),
      child: Row(
        children: [
          Icon(
            accepted ? Icons.check_circle_rounded : Icons.cancel_rounded,
            color: accepted ? P.ok : P.inkFaint,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              accepted
                  ? 'Accepted. Pantheon is on it.'
                  : 'You dismissed this idea.',
              style: PT.small,
            ),
          ),
        ],
      ),
    );
  }
}
