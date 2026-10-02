// Task sheet: one session task (turn) as a checklist of steps —
// MAIN steps, then one SUBAGENT NN section per delegated child run —
// with step detail pushed inside the sheet.
//
// Styled after the Muse-app task reference: dark sheet, status
// pill, mono-caps section labels, step rows with a status icon, bold
// title, dim summary, and a chevron. All content derives from the
// run-detail contract (see models/task_step.dart); child runs load
// lazily through [PantheonApi.runDetail] when the sheet opens and
// are cached for the sheet's lifetime.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/models.dart';
import '../services/app_preferences.dart';
import '../services/pantheon_api.dart';
import '../theme.dart';
import 'forms.dart';
import 'session_timeline.dart';
import 'states.dart';

/// Open the task sheet for [task]. Opening marks the task seen: the
/// persisted last-seen updatedMs for the run advances to (at least)
/// this task's updatedMs, clearing its unseen dot in the task list.
Future<void> showTaskSheet(
  BuildContext context, {
  required PantheonRun run,
  required SessionTask task,
  required PantheonApi api,
  String? anchorChildRunId,
}) async {
  final prefs = AppPreferences.instance;
  final seen = await prefs.taskSeenMs(run.id);
  if (task.updatedMs > seen) {
    await prefs.setTaskSeenMs(run.id, task.updatedMs);
  }
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: P.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollController) => TaskSheet(
        run: run,
        task: task,
        api: api,
        anchorChildRunId: anchorChildRunId,
        scrollController: scrollController,
      ),
    ),
  );
}

class TaskSheet extends StatefulWidget {
  final PantheonRun run;
  final SessionTask task;
  final PantheonApi api;

  /// Child run id whose SUBAGENT section to scroll to on open.
  final String? anchorChildRunId;

  /// Scroll controller owned by the enclosing DraggableScrollableSheet.
  final ScrollController? scrollController;

  const TaskSheet({
    super.key,
    required this.run,
    required this.task,
    required this.api,
    this.anchorChildRunId,
    this.scrollController,
  });

  @override
  State<TaskSheet> createState() => _TaskSheetState();
}

class _TaskSheetState extends State<TaskSheet> {
  /// Step shown in the in-sheet detail view (null = step list).
  TaskStep? _detailStep;

  /// Child-run fetches, one per delegated child run, cached for the
  /// sheet's lifetime. A retry removes the entry and refetches.
  final Map<String, Future<PantheonRun>> _childFutures = {};

  /// Section keys for scroll-to-subagent, keyed by child run id.
  final Map<String, GlobalKey> _sectionKeys = {};
  bool _anchored = false;

  SessionTask get _task => widget.task;

  @override
  void initState() {
    super.initState();
    // Lazy per spec: child runs load when the sheet opens.
    for (final id in _task.subagentRunIds) {
      _childFuture(id);
    }
  }

  Future<PantheonRun> _childFuture(String childRunId) => _childFutures
      .putIfAbsent(childRunId, () => widget.api.runDetail(childRunId));

  GlobalKey _sectionKey(String childRunId) =>
      _sectionKeys.putIfAbsent(childRunId, () => GlobalKey());

  /// Scroll the anchored SUBAGENT section into view once it exists.
  /// Called after the first frame and again whenever a child run
  /// finishes loading (the section grows, so re-anchor once).
  void _maybeScrollToAnchor() {
    final anchor = widget.anchorChildRunId;
    if (anchor == null || _anchored) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _anchored) return;
      final ctx = _sectionKeys[anchor]?.currentContext;
      if (ctx == null) return;
      _anchored = true;
      Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 300), alignment: 0.1);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetHandle(),
          _detailStep == null ? _header() : _detailHeader(_detailStep!),
          const Divider(height: 1),
          Expanded(
            child:
                _detailStep == null ? _stepList() : _stepDetail(_detailStep!),
          ),
          if (_detailStep == null &&
              _task.status == SessionTaskStatus.inProgress)
            _workingRow(),
        ],
      ),
    );
  }

  // -- Header ---------------------------------------------------------------

  Widget _header() {
    final task = _task;
    final badge = tlStatusBadge(switch (task.status) {
      SessionTaskStatus.inProgress => 'running',
      SessionTaskStatus.completed => 'completed',
      SessionTaskStatus.failed => 'failed',
    });
    final pillLabel = switch (task.status) {
      SessionTaskStatus.inProgress => 'In progress',
      SessionTaskStatus.completed => 'Completed',
      SessionTaskStatus.failed => 'Failed',
    };
    final subtitle = task.liveSummary.isNotEmpty
        ? task.liveSummary
        : (task.steps.isEmpty ? '' : task.steps.last.title);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                child: Text(pillLabel,
                    style: PT.label.copyWith(fontSize: 12, color: badge.color)),
              ),
              const SizedBox(width: 10),
              Text(clockTime(task.startedMs), style: PT.meta),
              const Spacer(),
              IconButton(
                icon: Icon(Icons.close_rounded, color: P.inkSecondary),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            task.title,
            style: PT.sectionTitle.copyWith(fontSize: 19),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(subtitle,
                style: PT.meta, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ],
      ),
    );
  }

  Widget _detailHeader(TaskStep step) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 14),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back_rounded, color: P.inkSecondary),
            onPressed: () => setState(() => _detailStep = null),
          ),
          Expanded(
            child: Text(
              step.title,
              style: PT.sectionTitle.copyWith(fontSize: 17),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // -- Step list --------------------------------------------------------------

  Widget _stepList() {
    _maybeScrollToAnchor();
    final children = <Widget>[
      _sectionLabel('MAIN'),
      if (_task.steps.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
          child: Text('No tool steps recorded for this task.', style: PT.meta),
        )
      else
        for (final s in _task.steps) _stepRow(s),
    ];
    for (var i = 0; i < _task.subagentRunIds.length; i++) {
      final childId = _task.subagentRunIds[i];
      final nn = (i + 1).toString().padLeft(2, '0');
      children.add(KeyedSubtree(
        key: _sectionKey(childId),
        child: _sectionLabel('SUBAGENT $nn'),
      ));
      children.add(_subagentBody(childId));
    }
    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.only(bottom: 24),
      children: children,
    );
  }

  Widget _sectionLabel(String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Text(label,
              style: PT.label.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: P.inkSecondary)),
        ),
      ],
    );
  }

  Widget _subagentBody(String childId) {
    return FutureBuilder<PantheonRun>(
      future: _childFuture(childId),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
            child: Row(children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              Text("Loading the agent's work…", style: PT.meta),
            ]),
          );
        }
        if (snap.hasError || snap.data == null) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
            child: Row(children: [
              Expanded(
                child: Text("Couldn't load this agent's work.", style: PT.meta),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _childFutures.remove(childId);
                  _childFuture(childId);
                }),
                child: Text('Retry', style: PT.small.copyWith(color: P.accent)),
              ),
            ]),
          );
        }
        final child = snap.data!;
        _maybeScrollToAnchor();
        final steps = taskStepsFromItems(
          child.transcript,
          live: isLiveRunStatus(child.status),
          actor: childId,
          runId: child.id,
          turnIndex: _task.turnIndex,
        );
        if (steps.isEmpty) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
            child: Text('Nothing recorded for this agent yet.', style: PT.meta),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [for (final s in steps) _stepRow(s)],
        );
      },
    );
  }

  Widget _stepRow(TaskStep s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _detailStep = s),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: _statusIcon(s.status),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.title,
                          style: PT.body.copyWith(
                              fontSize: 14.5, fontWeight: FontWeight.w600),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      if (s.summary.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(s.summary,
                              style: PT.meta,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(Icons.chevron_right_rounded,
                      color: P.inkMuted, size: 20),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1, indent: 20, endIndent: 20),
      ],
    );
  }

  /// Status icon: green check circle (done), spinner (running), red
  /// error icon — GlyphCircle colors, matching the Timeline card.
  Widget _statusIcon(TaskStepStatus status) {
    switch (status) {
      case TaskStepStatus.done:
        return const GlyphCircle(icon: Icons.check_rounded, color: P.ok);
      case TaskStepStatus.error:
        return const GlyphCircle(icon: Icons.close_rounded, color: P.err);
      case TaskStepStatus.running:
        return Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: P.accent.withValues(alpha: 0.13),
            border:
                Border.all(color: P.accent.withValues(alpha: 0.55), width: 1.2),
          ),
          child: const Padding(
            padding: EdgeInsets.all(6),
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
    }
  }

  /// Pinned live row at the bottom of the list while the task runs.
  Widget _workingRow() {
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: P.divider, width: 1)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text('Working', style: PT.small.copyWith(color: P.inkSecondary)),
        ],
      ),
    );
  }

  // -- Step detail ------------------------------------------------------------

  Widget _stepDetail(TaskStep step) {
    final statusWord = switch (step.status) {
      TaskStepStatus.running => 'Running',
      TaskStepStatus.done => 'Completed',
      TaskStepStatus.error => 'Failed',
    };
    final metaParts = <String>[
      statusWord,
      if (step.durationMs != null) formatDurationMs(step.durationMs!),
      if (step.startedMs != null) clockTime(step.startedMs!),
    ];
    final args = step.argsPretty.trim();
    final output = step.output.trim();
    return SingleChildScrollView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(metaParts.join(' · '), style: PT.meta),
          const SizedBox(height: 12),
          SelectableText(step.detail,
              style: PT.body.copyWith(fontSize: 13.5, color: P.inkSecondary)),
          if (args.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(step.kind == 'command' ? 'COMMAND' : 'ARGUMENTS',
                style: PT.monoEyebrow.copyWith(color: P.inkSecondary)),
            const SizedBox(height: 6),
            _CodeCard(text: step.argsPretty, copyMessage: 'Arguments copied.'),
          ],
          const SizedBox(height: 16),
          Text(step.status == TaskStepStatus.error ? 'ERROR' : 'OUTPUT',
              style: PT.monoEyebrow.copyWith(
                  color: step.status == TaskStepStatus.error
                      ? P.err
                      : P.inkSecondary)),
          const SizedBox(height: 6),
          if (output.isEmpty)
            Text('No output recorded.', style: PT.meta)
          else
            _CodeCard(
              text: step.output,
              copyMessage: 'Output copied.',
              maxHeight: 240,
            ),
        ],
      ),
    );
  }
}

/// Dark monospace card with a copy button, matching the Thoughts
/// sheet's args card. [maxHeight] caps the card with internal scroll
/// (used for long tool output).
class _CodeCard extends StatelessWidget {
  final String text;
  final String copyMessage;
  final double? maxHeight;

  const _CodeCard(
      {required this.text, required this.copyMessage, this.maxHeight});

  @override
  Widget build(BuildContext context) {
    final body = SelectableText(
      text,
      style: const TextStyle(
        fontFamily: 'JetBrainsMono',
        fontSize: 12,
        height: 1.5,
        color: Color(0xFFE8E8E8),
      ),
    );
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(P.r8),
        border: Border.all(color: P.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: text));
                toast(context, copyMessage);
                HapticFeedback.lightImpact();
              },
              child: const Padding(
                padding: EdgeInsets.fromLTRB(8, 8, 8, 4),
                child: Icon(Icons.copy_rounded,
                    size: 15, color: Color(0xFF9A8BD0)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: maxHeight == null
                ? body
                : ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: maxHeight!),
                    child: SingleChildScrollView(child: body),
                  ),
          ),
        ],
      ),
    );
  }
}
