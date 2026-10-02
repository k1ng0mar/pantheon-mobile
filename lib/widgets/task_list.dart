// Timeline tab content: the session's tasks (one per turn), grouped
// by day, newest first. Tapping a task opens its [TaskSheet].
//
// Seen-state: a task shows a red dot while its updatedMs is newer
// than the last-seen updatedMs persisted for the run (see
// [AppPreferences.taskSeenMs]); opening the sheet advances it.

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/app_preferences.dart';
import '../services/pantheon_api.dart';
import '../theme.dart';
import 'agent_avatar.dart';
import 'states.dart';
import 'task_sheet.dart';

class SessionTaskList extends StatefulWidget {
  final PantheonRun run;
  final PantheonApi api;

  const SessionTaskList({super.key, required this.run, required this.api});

  @override
  State<SessionTaskList> createState() => _SessionTaskListState();
}

class _SessionTaskListState extends State<SessionTaskList> {
  int _seenMs = 0;
  bool _seenLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadSeen();
  }

  @override
  void didUpdateWidget(SessionTaskList old) {
    super.didUpdateWidget(old);
    if (old.run.id != widget.run.id) _loadSeen();
  }

  Future<void> _loadSeen() async {
    final ms = await AppPreferences.instance.taskSeenMs(widget.run.id);
    if (mounted) {
      setState(() {
        _seenMs = ms;
        _seenLoaded = true;
      });
    }
  }

  Future<void> _openTask(SessionTask task) async {
    await showTaskSheet(context, run: widget.run, task: task, api: widget.api);
    // Opening marked the task seen; refresh the dot state.
    await _loadSeen();
  }

  @override
  Widget build(BuildContext context) {
    final tasks = sessionTasksForRun(widget.run);
    if (tasks.isEmpty) {
      return const EmptyState(
        icon: Icons.task_alt_rounded,
        title: 'No tasks yet',
        body: 'Tasks appear here as the session works through your messages.',
      );
    }
    final groups = groupTasksByDay(tasks);
    final children = <Widget>[];
    for (final g in groups) {
      children.add(_dayHeader(g.day));
      for (final t in g.tasks) {
        children.add(_taskRow(t));
      }
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: children,
    );
  }

  /// Day header: Today / Yesterday / "Tue, Oct 2".
  Widget _dayHeader(DateTime day) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Text(taskDayLabel(day), style: PT.overline),
    );
  }

  Widget _taskRow(SessionTask task) {
    final unseen = _seenLoaded && task.updatedMs > _seenMs;
    return InkWell(
      onTap: () => _openTask(task),
      borderRadius: BorderRadius.circular(P.r16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AgentAvatar(size: 38),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(task.title,
                      style: PT.rowTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  if (task.liveSummary.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(task.liveSummary,
                          style: PT.meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(clockTime(task.startedMs), style: PT.faint),
                if (unseen)
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: P.err,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Today / Yesterday / "Tue, Oct 2" (manual names; no intl dependency).
String taskDayLabel(DateTime day) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];
  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return '${weekdays[day.weekday - 1]}, ${months[day.month - 1]} ${day.day}';
}
