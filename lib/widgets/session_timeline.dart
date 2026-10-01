import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme.dart';

/// The session activity transcript card, shared by the Timeline tab and
/// the agent activity screen.
///
/// One dark rounded card with a header block (title, status chip +
/// outcome time, outcome detail when it exists), then MAIN / SUBAGENT NN
/// sections whose rows hang off a dashed rail with status glyphs. Rows
/// expand on tap. Detail lines only render when they have real content —
/// empty strings never produce a line.
class SessionTimeline extends StatefulWidget {
  final PantheonRun run;

  /// True while a manual turn retry is in flight (drives the retry
  /// button's spinner and disables double-taps).
  final bool retrying;

  /// Retry callback for a failed run. Null hides the retry button —
  /// the agent activity screen passes nothing.
  final VoidCallback? onRetry;

  const SessionTimeline({
    super.key,
    required this.run,
    this.retrying = false,
    this.onRetry,
  });

  @override
  State<SessionTimeline> createState() => _SessionTimelineState();
}

class _SessionTimelineState extends State<SessionTimeline> {
  /// Timeline rows the user expanded, by item seq.
  final Set<int> _expanded = {};

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: P.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: P.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          ..._blocks(),
        ],
      ),
    );
  }

  /// Card header: title, status chip + outcome time, and the outcome
  /// detail as a separated paragraph when it exists.
  Widget _header() {
    final run = widget.run;
    TimelineItem? terminal;
    for (final e in run.timeline) {
      if (tlIsTerminalKind(e.kind)) terminal = e;
    }
    final detail = (terminal?.detail ?? '').trim();
    final outcomeTs = terminal?.tsMs ?? run.createdMs;
    final badge = tlStatusBadge(run.status);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            run.title.trim().isNotEmpty ? run.title.trim() : 'Session',
            style: PT.cardTitle.copyWith(fontSize: 19),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: badge.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: badge.color.withValues(alpha: 0.45)),
                ),
                child: Text(badge.label,
                    style: PT.label.copyWith(fontSize: 12, color: badge.color)),
              ),
              const SizedBox(width: 10),
              Text(clockTime(outcomeTs), style: PT.meta),
            ],
          ),
          if (detail.isNotEmpty) ...[
            const SizedBox(height: 12),
            Divider(color: P.divider, height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: SelectableText(detail,
                  style: PT.body.copyWith(
                      fontSize: 13.5, color: P.inkSecondary)),
            ),
          ],
          if (run.status == 'failed' && widget.onRetry != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: widget.retrying ? null : widget.onRetry,
                icon: widget.retrying
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded, size: 18),
                label: Text(widget.retrying ? 'Retrying…' : 'Retry turn'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: P.accent,
                  side: BorderSide(color: P.accent.withValues(alpha: 0.5)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Timeline body: section headers plus rows. Subagent spans become
  /// numbered SUBAGENT sections; everything else is MAIN. A row draws
  /// its dashed rail only when the next block is a plain row (no
  /// section header in between).
  List<Widget> _blocks() {
    final run = widget.run;
    final segments = <TimelineSegment>[];
    var subagents = 0;
    var inSubagent = false;
    var mainAdded = false;
    for (final e in run.timeline) {
      String? section;
      String? subtitle;
      if (tlIsAgentKind(e.kind)) {
        if (!inSubagent) {
          subagents++;
          final agent = (e.detail ?? '').trim();
          section =
              'SUBAGENT ${subagents.toString().padLeft(2, '0')}';
          subtitle = agent.isNotEmpty ? agent : null;
          inSubagent = true;
        }
      } else {
        inSubagent = false;
        if (!mainAdded) {
          section = 'MAIN';
          mainAdded = true;
        }
      }
      segments.add(
          TimelineSegment(section: section, subtitle: subtitle, item: e));
    }
    final blocks = <Widget>[];
    for (var i = 0; i < segments.length; i++) {
      final s = segments[i];
      if (s.section != null) {
        blocks.add(_section(s.section!, subtitle: s.subtitle));
      }
      final next = i + 1 < segments.length ? segments[i + 1] : null;
      blocks.add(_row(s.item,
          showRail: next != null && next.section == null));
    }
    return blocks;
  }

  Widget _section(String label, {String? subtitle}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(color: P.divider, height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(label,
                    style: PT.label.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                        color: P.inkSecondary)),
              ),
              if (subtitle != null)
                Flexible(
                  child: Text(subtitle,
                      style: PT.meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(TimelineItem item, {required bool showRail}) {
    final expanded = _expanded.contains(item.seq);
    final detail = (item.detail ?? '').trim();
    final spec = tlGlyph(item.kind);
    final body = IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              const SizedBox(height: 2),
              GlyphCircle(icon: spec.icon, color: spec.color),
              if (showRail) const Expanded(child: DashedRail()),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tlTitle(item.kind),
                      style: PT.body.copyWith(
                          fontSize: 14.5, fontWeight: FontWeight.w600)),
                  if (detail.isNotEmpty && !expanded)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(detail,
                          style: PT.meta,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis),
                    ),
                  if (expanded) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: SelectableText(detail,
                          style: PT.body.copyWith(
                              fontSize: 13.5, color: P.inkSecondary)),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(timeAgo(item.tsMs), style: PT.faint),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (detail.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                  expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.chevron_right_rounded,
                  color: P.inkMuted,
                  size: 20),
            ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 14, 10),
      child: detail.isEmpty
          ? body
          : InkWell(
              onTap: () => setState(() => expanded
                  ? _expanded.remove(item.seq)
                  : _expanded.add(item.seq)),
              borderRadius: BorderRadius.circular(8),
              child: body,
            ),
    );
  }
}

/// Status badge for a run: human label + chip color.
({String label, Color color}) tlStatusBadge(String status) {
  switch (status) {
    case 'failed':
      return (label: 'Error', color: P.err);
    case 'canceled':
      return (label: 'Canceled', color: P.err);
    case 'awaiting_approval':
      return (label: 'Awaiting approval', color: P.warn);
    case 'running':
      return (label: 'Live', color: P.accent);
    case 'completed':
      return (label: 'Completed', color: P.ok);
    default:
      return (label: status, color: P.inkMuted);
  }
}

bool tlIsAgentKind(String kind) =>
    kind == 'agent_spawned' ||
    kind == 'agent_message' ||
    kind == 'agent_completed';

bool tlIsTerminalKind(String kind) =>
    kind == 'run_failed' ||
    kind == 'run_canceled' ||
    kind == 'run_completed';

/// One timeline block: an optional section header plus its row.
class TimelineSegment {
  final String? section;
  final String? subtitle;
  final TimelineItem item;
  const TimelineSegment({this.section, this.subtitle, required this.item});
}

/// Status glyph spec for a timeline kind.
class TimelineGlyphSpec {
  final IconData icon;
  final Color color;
  const TimelineGlyphSpec(this.icon, this.color);
}

/// The status glyph: tinted circle with an icon.
class GlyphCircle extends StatelessWidget {
  final IconData icon;
  final Color color;

  const GlyphCircle({super.key, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.13),
        border: Border.all(color: color.withValues(alpha: 0.55), width: 1.2),
      ),
      child: Icon(icon, size: 13, color: color),
    );
  }
}

/// Thin dashed vertical rail connecting timeline glyphs.
class DashedRail extends StatelessWidget {
  const DashedRail({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => CustomPaint(
        size: Size(2, constraints.maxHeight),
        painter: _DashPainter(),
      ),
    );
  }
}

class _DashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = P.borderStrong
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    const dashH = 5.0;
    const gapH = 5.0;
    var y = 2.0;
    while (y < size.height - 2) {
      final end = (y + dashH).clamp(0.0, size.height);
      canvas.drawLine(
          Offset(size.width / 2, y), Offset(size.width / 2, end), paint);
      y += dashH + gapH;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Status glyph for a timeline kind.
TimelineGlyphSpec tlGlyph(String kind) {
  switch (kind) {
    case 'run_completed':
    case 'turn_completed':
    case 'agent_completed':
    case 'approval_granted':
    case 'model_completed':
      return TimelineGlyphSpec(Icons.check_rounded, P.ok);
    case 'run_failed':
    case 'approval_denied':
      return TimelineGlyphSpec(Icons.close_rounded, P.err);
    case 'run_canceled':
      return TimelineGlyphSpec(Icons.close_rounded, P.warn);
    case 'approval_requested':
    case 'turn_parked':
      return TimelineGlyphSpec(Icons.schedule_rounded, P.warn);
    case 'input_requested':
      return TimelineGlyphSpec(Icons.question_answer_rounded, P.accent);
    case 'input_provided':
      return TimelineGlyphSpec(Icons.check_rounded, P.ok);
    case 'agent_spawned':
      return TimelineGlyphSpec(Icons.person_add_alt_rounded, P.info);
    case 'agent_message':
      return TimelineGlyphSpec(Icons.chat_bubble_outline_rounded, P.info);
    case 'titled':
      return TimelineGlyphSpec(Icons.edit_rounded, P.inkMuted);
    case 'usage':
      return TimelineGlyphSpec(Icons.pie_chart_outline_rounded, P.inkMuted);
    case 'run_started':
    case 'turn_started':
    case 'model_requested':
      return TimelineGlyphSpec(Icons.fiber_manual_record_rounded, P.accent);
    case 'tool_started':
      return TimelineGlyphSpec(Icons.build_rounded, P.accent);
    case 'tool_completed':
      return TimelineGlyphSpec(Icons.check_rounded, P.ok);
    case 'model_fallback':
      return TimelineGlyphSpec(Icons.swap_horiz_rounded, P.warn);
    default:
      return TimelineGlyphSpec(Icons.info_outline_rounded, P.inkMuted);
  }
}

/// Bold row title for a timeline kind. Unknown kinds are humanized;
/// raw snake_case never reaches the screen.
String tlTitle(String kind) {
  switch (kind) {
    case 'run_started':
      return 'Session started';
    case 'run_completed':
      return 'Run completed';
    case 'run_failed':
      return 'Run failed';
    case 'run_canceled':
      return 'Run canceled';
    case 'turn_started':
      return 'Turn started';
    case 'turn_completed':
      return 'Turn completed';
    case 'turn_parked':
      return 'Turn parked';
    case 'model_requested':
      return 'Model request';
    case 'model_completed':
      return 'Model response';
    case 'usage':
      return 'Usage';
    case 'approval_requested':
      return 'Approval requested';
    case 'approval_granted':
      return 'Approval granted';
    case 'approval_denied':
      return 'Approval denied';
    case 'input_requested':
      return 'Clarification needed';
    case 'input_provided':
      return 'Clarification answered';
    case 'agent_spawned':
      return 'Subagent started';
    case 'agent_message':
      return 'Subagent update';
    case 'agent_completed':
      return 'Subagent finished';
    case 'titled':
      return 'Session renamed';
    case 'tool_started':
      return 'Tool started';
    case 'tool_completed':
      return 'Tool finished';
    case 'model_fallback':
      return 'Model fallback';
    default:
      final words = kind.replaceAll('_', ' ').trim();
      if (words.isEmpty) return 'Event';
      return words[0].toUpperCase() + words.substring(1);
  }
}
