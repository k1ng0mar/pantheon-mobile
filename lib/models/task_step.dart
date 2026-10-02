// Task / step model for the session Timeline tab.
//
// A **task** is one turn of a session: the transcript segmented at
// user messages. A **step** is one tool call inside a turn. Everything
// here is derived app-side from the existing run-detail contract — no
// API change — and all titles, summaries, and detail prose come from
// deterministic templates over real fields (tool name, arguments,
// output, timestamps). Nothing is fabricated: a step with no recorded
// output renders no summary line, and the detail prose only states
// facts parseable from the call and its result.
//
// The model is agent-wide on purpose: every step carries the owning
// [TaskStep.runId], its [TaskStep.turnIndex], and the
// [TaskStep.childRunId] a delegate step spawned, so a future global
// activity feed can reuse these classes without reshaping them.

import 'dart:convert';

import 'pantheon_run.dart';

/// Tool name → step kind. Covers the contract kinds:
/// command | tool | delegate | file-search | web-search | read | edit.
/// (Moved from session_detail_screen; the Thoughts sheet calls this
/// through its original private alias, behavior unchanged.)
String stepKindFor(String name) {
  final n = name.toLowerCase();
  if (n.contains('delegate') ||
      n.contains('subagent') ||
      n.contains('dispatch') ||
      n.contains('swarm')) {
    return 'delegate';
  }
  if (n.contains('web') &&
      (n.contains('search') ||
          n.contains('lookup') ||
          n.contains('fetch') ||
          n.contains('crawl'))) {
    return 'web-search';
  }
  if (n.contains('grep') ||
      n.contains('glob') ||
      n.contains('find') ||
      n.contains('rg') ||
      n.contains('lookup')) {
    return 'file-search';
  }
  // Rescue order matters: the bare `search` below would otherwise call
  // file and memory searches web searches. `search_files`,
  // `code_search`, and `memory_search` are named narrowly on purpose.
  if (n.contains('search') && (n.contains('file') || n.contains('code'))) {
    return 'file-search';
  }
  if (n.contains('search') && n.contains('memory')) return 'tool';
  if (n.contains('search')) return 'web-search';
  if (n.contains('exec') ||
      n.contains('command') ||
      n.contains('shell') ||
      n.contains('bash') ||
      n.contains('terminal')) {
    return 'command';
  }
  if (n.contains('edit') ||
      n.contains('write') ||
      n.contains('patch') ||
      n.contains('apply')) {
    return 'edit';
  }
  if (n.contains('read')) return 'read';
  return 'tool';
}

/// MCP-ish names like `filesystem__read_file` → "Read File".
String humanToolName(String name) {
  var n = name;
  final sep = n.lastIndexOf('__');
  if (sep >= 0) n = n.substring(sep + 2);
  final words = n
      .split(RegExp(r'[_\-\s]+'))
      .where((w) => w.isNotEmpty)
      .map((w) => '${w[0].toUpperCase()}${w.substring(1)}');
  final label = words.join(' ');
  return label.isEmpty ? name : label;
}

Map<String, dynamic>? argsMapOf(String argsJson) {
  try {
    final v = jsonDecode(argsJson);
    if (v is Map) return v.cast<String, dynamic>();
  } catch (_) {}
  return null;
}

String? nonEmptyArgValue(dynamic v) =>
    v is String && v.trim().isNotEmpty ? v.trim() : null;

/// Delegate call extras parsed from the call arguments. Key names vary
/// across backends, so probe the common ones.
String? delegateAgentOf(Map<String, dynamic> args) =>
    nonEmptyArgValue(args['agent']) ??
    nonEmptyArgValue(args['subagent_type']) ??
    nonEmptyArgValue(args['subagent']) ??
    nonEmptyArgValue(args['name']);

String? delegateTaskOf(Map<String, dynamic> args) =>
    nonEmptyArgValue(args['task']) ??
    nonEmptyArgValue(args['description']) ??
    nonEmptyArgValue(args['summary']) ??
    nonEmptyArgValue(args['title']);

String? delegatePromptOf(Map<String, dynamic> args) =>
    nonEmptyArgValue(args['prompt']) ??
    nonEmptyArgValue(args['message']) ??
    nonEmptyArgValue(args['instructions']) ??
    nonEmptyArgValue(args['input']);

/// Best-effort error detection: the backend has no machine-readable
/// error marker on tool results, so match the common "Error…" prefix.
bool looksLikeToolError(String content) =>
    content.trimLeft().toLowerCase().startsWith('error');

String prettyArgsJson(String argsJson) {
  try {
    return const JsonEncoder.withIndent('  ').convert(jsonDecode(argsJson));
  } catch (_) {
    return argsJson;
  }
}

String truncateTo(String s, int n) =>
    s.length <= n ? s : '${s.substring(0, n).trimRight()}…';

/// "64 ms" / "1.1 s" / "2m 5s" from a millisecond duration.
String formatDurationMs(int ms) {
  if (ms < 1000) return '$ms ms';
  final s = ms / 1000;
  if (s < 60) {
    final fixed = s.toStringAsFixed(1);
    return '${fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed} s';
  }
  final m = s ~/ 60;
  final rem = (s % 60).round();
  return rem == 0 ? '${m}m' : '${m}m ${rem}s';
}

/// Live run statuses (mirrors the session screen's rule).
bool isLiveRunStatus(String status) =>
    status == 'running' || status == 'awaiting_approval';

/// Backend duration_ms wins (on the call, then on the result row);
/// otherwise fall back to the owner→result timestamp delta. Same rule
/// as the Thoughts sheet's step derivation.
int? resolveToolDurationMs(
    ToolCallRef call, TranscriptItem? result, int? ownerTsMs) {
  final direct = call.durationMs ?? result?.durationMs;
  if (direct != null && direct >= 0) return direct;
  if (result?.tsMs != null && ownerTsMs != null) {
    final ms = result!.tsMs! - ownerTsMs;
    if (ms >= 0) return ms;
  }
  return null;
}

enum TaskStepStatus { running, done, error }

enum SessionTaskStatus { inProgress, completed, failed }

/// One tool call inside a turn, with deterministic presentation
/// ([title], [summary], [detail]) derived from its real fields.
class TaskStep {
  /// Which row in the Tasks/Thoughts schema this step came from:
  /// `'main'` for the session's own calls, otherwise the child run id
  /// whose transcript produced the step.
  final String actor;

  /// The run whose transcript owns this step.
  final String runId;

  /// Index of the turn (task) this step belongs to, within [runId]'s
  /// session. Child-run steps carry the delegating task's index.
  final int turnIndex;

  final ToolCallRef call;
  final TranscriptItem? result;

  final String kind;
  final TaskStepStatus status;
  final int? startedMs;
  final int? durationMs;

  /// For a delegate call: the child run it spawned, when the backend
  /// recorded the link.
  final String? childRunId;

  /// Transcript index of the assistant item that owns this step.
  final int transcriptIndex;

  final String title;
  final String summary;
  final String detail;

  TaskStep._({
    required this.actor,
    required this.runId,
    required this.turnIndex,
    required this.call,
    required this.result,
    required this.kind,
    required this.status,
    required this.startedMs,
    required this.durationMs,
    required this.childRunId,
    required this.transcriptIndex,
    required this.title,
    required this.summary,
    required this.detail,
  });

  factory TaskStep.fromCall({
    required ToolCallRef call,
    required TranscriptItem? result,
    required bool live,
    required String actor,
    required String runId,
    required int turnIndex,
    required int transcriptIndex,
    int? ownerTsMs,
  }) {
    // A call with no result on a settled run is an error, not pending.
    final status = result != null
        ? (looksLikeToolError(result.content)
            ? TaskStepStatus.error
            : TaskStepStatus.done)
        : (live ? TaskStepStatus.running : TaskStepStatus.error);
    final duration = resolveToolDurationMs(call, result, ownerTsMs);
    return TaskStep._(
      actor: actor,
      runId: runId,
      turnIndex: turnIndex,
      call: call,
      result: result,
      kind: stepKindFor(call.name),
      status: status,
      startedMs: call.startedMs ?? ownerTsMs,
      durationMs: duration,
      childRunId: call.childRunId,
      transcriptIndex: transcriptIndex,
      title: deriveStepTitle(call),
      summary: deriveStepSummary(
          call: call, result: result, status: status, durationMs: duration),
      detail: deriveStepDetail(
          call: call, result: result, status: status, durationMs: duration),
    );
  }

  bool get isDelegate => kind == 'delegate';

  /// Raw arguments JSON, pretty-printed when parseable.
  String get argsPretty => prettyArgsJson(call.arguments);

  /// The tool result text ('' when no result was recorded).
  String get output => result?.content ?? '';
}

/// Argument keys probed for the salient value a step acted on, in
/// priority order (path-like first, then command/query/task text).
const salientArgKeys = [
  'path',
  'file',
  'filepath',
  'file_path',
  'dir',
  'directory',
  'command',
  'cmd',
  'query',
  'pattern',
  'task',
  'message',
];

/// First non-empty string argument among [keys].
String? salientArg(Map<String, dynamic> args,
    [List<String> keys = salientArgKeys]) {
  for (final k in keys) {
    final v = nonEmptyArgValue(args[k]);
    if (v != null) return v;
  }
  return null;
}

/// Whether this command lists a directory (`ls …`, `find …`, `dir …`
/// as the first token).
bool isListCommand(String command) {
  final first = command.trim().split(RegExp(r'\s+')).first.toLowerCase();
  final base = first.split('/').last;
  return base == 'ls' || base == 'find' || base == 'dir';
}

/// The directory a list-style step targeted: an explicit path/dir
/// argument, else the first non-flag token after the command word.
String? listTarget(Map<String, dynamic> args, String? command) {
  final explicit =
      salientArg(args, const ['dir', 'directory', 'path', 'file', 'filepath']);
  if (explicit != null) return explicit;
  if (command != null) {
    final tokens = command.trim().split(RegExp(r'\s+'));
    for (final t in tokens.skip(1)) {
      if (!t.startsWith('-')) return t;
    }
  }
  return null;
}

/// Deterministic step title from kind + salient arguments.
String deriveStepTitle(ToolCallRef call) {
  final kind = stepKindFor(call.name);
  final name = call.name.toLowerCase();
  final args = argsMapOf(call.arguments) ?? const {};
  final path =
      salientArg(args, const ['path', 'file', 'filepath', 'file_path']);
  final command = salientArg(args, const ['command', 'cmd']);

  if (kind == 'delegate') {
    final task = delegateTaskOf(args) ?? delegatePromptOf(args);
    return task != null
        ? 'Delegated ${truncateTo(task, 48)}'
        : humanToolName(call.name);
  }
  if (name.contains('list') ||
      (kind == 'command' && command != null && isListCommand(command))) {
    final dir = listTarget(args, command);
    return dir != null ? 'Listed ${truncateTo(dir, 48)}' : 'Listed files';
  }
  switch (kind) {
    case 'read':
      return path != null
          ? 'Read ${truncateTo(path, 48)}'
          : humanToolName(call.name);
    case 'edit':
      final wrote = name.contains('write') || name.contains('create');
      if (path != null) {
        return '${wrote ? 'Wrote' : 'Edited'} ${truncateTo(path, 48)}';
      }
      return humanToolName(call.name);
    case 'command':
      return command != null
          ? 'Ran ${truncateTo(command, 48)}'
          : humanToolName(call.name);
    case 'file-search':
      final target = salientArg(
          args, const ['pattern', 'path', 'dir', 'directory', 'query']);
      return target != null
          ? 'Searched ${truncateTo(target, 48)}'
          : humanToolName(call.name);
    case 'web-search':
      final q = salientArg(args, const ['query', 'q', 'pattern']);
      return q != null
          ? 'Searched web for ${truncateTo(q, 48)}'
          : humanToolName(call.name);
    default:
      final arg = salientArg(args);
      return arg != null
          ? '${humanToolName(call.name)} ${truncateTo(arg, 48)}'
          : humanToolName(call.name);
  }
}

final _exitCodeRe = RegExp(r'exit code[:\s]+(-?\d+)', caseSensitive: false);

/// Exit code parseable from a tool result, when the backend printed
/// one (e.g. "Exit code: 0").
int? parseExitCode(String output) {
  final m = _exitCodeRe.firstMatch(output);
  return m == null ? null : int.tryParse(m.group(1)!);
}

/// Deterministic one-line outcome summary. Empty when there is
/// nothing factual to say — callers hide empty summaries, never
/// render them.
String deriveStepSummary({
  required ToolCallRef call,
  required TranscriptItem? result,
  required TaskStepStatus status,
  required int? durationMs,
}) {
  final output = (result?.content ?? '').trim();
  if (output.isNotEmpty) {
    final firstLine = output
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');
    final parts = <String>[];
    final exit = parseExitCode(output);
    if (exit != null && !firstLine.toLowerCase().contains('exit code')) {
      parts.add('Exit code $exit');
    }
    if (durationMs != null) parts.add(formatDurationMs(durationMs));
    if (firstLine.isNotEmpty) parts.add(truncateTo(firstLine, 120));
    return truncateTo(parts.join(' · '), 160);
  }
  // No output recorded: fall back to the factual thing the step
  // acted on (the command, path, or query from its arguments).
  final args = argsMapOf(call.arguments) ?? const {};
  final arg = salientArg(args);
  if (arg != null) return truncateTo(arg.replaceAll(RegExp(r'\s+'), ' '), 120);
  return '';
}

/// Deterministic detail prose: what the step did, then its outcome.
/// Only facts present in the call/result are stated.
String deriveStepDetail({
  required ToolCallRef call,
  required TranscriptItem? result,
  required TaskStepStatus status,
  required int? durationMs,
}) {
  final kind = stepKindFor(call.name);
  final name = call.name.toLowerCase();
  final args = argsMapOf(call.arguments) ?? const {};
  final path =
      salientArg(args, const ['path', 'file', 'filepath', 'file_path']);
  final command = salientArg(args, const ['command', 'cmd']);
  final output = (result?.content ?? '').trim();

  final String base;
  if (kind == 'delegate') {
    final task = delegateTaskOf(args) ?? delegatePromptOf(args);
    base = task != null
        ? 'Delegated a subagent task: ${truncateTo(task, 200)}.'
        : 'Delegated work to a subagent.';
  } else if (name.contains('list') ||
      (kind == 'command' && command != null && isListCommand(command))) {
    final dir = listTarget(args, command);
    base = dir != null
        ? 'Listed the contents of $dir.'
        : 'Listed directory contents.';
  } else {
    base = switch (kind) {
      'read' => path != null ? 'Read the file at $path.' : 'Read a file.',
      'edit' => (name.contains('write') || name.contains('create'))
          ? (path != null ? 'Wrote the file at $path.' : 'Wrote a file.')
          : (path != null ? 'Edited the file at $path.' : 'Edited a file.'),
      'command' => command != null
          ? 'Ran the command: ${truncateTo(command, 200)}.'
          : 'Ran a command.',
      'file-search' => _fileSearchSentence(args, path),
      'web-search' => () {
          final q = salientArg(args, const ['query', 'q', 'pattern']);
          return q != null ? 'Searched the web for $q.' : 'Searched the web.';
        }(),
      _ => () {
          final arg = salientArg(args);
          return arg != null
              ? '${humanToolName(call.name)}: ${truncateTo(arg, 200)}.'
              : '${humanToolName(call.name)} step.';
        }(),
    };
  }

  final exit = output.isEmpty ? null : parseExitCode(output);
  final dur = durationMs != null ? formatDurationMs(durationMs) : null;
  final String outcome;
  switch (status) {
    case TaskStepStatus.running:
      outcome = 'It is still running; no output has been recorded yet.';
    case TaskStepStatus.error:
      if (output.isEmpty) {
        outcome = 'It ended without a recorded result.';
      } else if (exit != null) {
        outcome =
            'It failed with exit code $exit${dur != null ? ' after $dur' : ''}.';
      } else if (looksLikeToolError(output)) {
        outcome =
            'The tool reported an error${dur != null ? ' after $dur' : ''}.';
      } else {
        outcome = 'It ended with an error${dur != null ? ' after $dur' : ''}.';
      }
    case TaskStepStatus.done:
      if (output.isEmpty) {
        outcome = 'It completed with no output.';
      } else {
        final facts = <String>[
          if (exit != null) 'with exit code $exit',
          if (dur != null) 'in $dur',
        ];
        outcome = facts.isEmpty
            ? 'It completed.'
            : 'It completed ${facts.join(' ')}.';
      }
  }
  return '$base $outcome';
}

String _fileSearchSentence(Map<String, dynamic> args, String? path) {
  final pattern = salientArg(args, const ['pattern', 'query']);
  final buf = StringBuffer('Searched files');
  if (pattern != null) buf.write(' for $pattern');
  if (path != null) buf.write(' in $path');
  buf.write('.');
  return buf.toString();
}

/// Derive the tool-call steps of one transcript segment, with the
/// same rules as the Thoughts sheet: results matched by tool_call_id,
/// a call with no result is running on a live run and an error on a
/// settled one. Reasoning rows and orphan results are not steps here
/// (the Thoughts sheet owns those).
List<TaskStep> taskStepsFromItems(
  List<TranscriptItem> items, {
  required bool live,
  required String actor,
  required String runId,
  required int turnIndex,
  int transcriptOffset = 0,
}) {
  final results = <String, TranscriptItem>{};
  for (final t in items) {
    if (t.role == 'tool' && t.toolCallId != null) {
      results.putIfAbsent(t.toolCallId!, () => t);
    }
  }
  final steps = <TaskStep>[];
  for (var i = 0; i < items.length; i++) {
    final t = items[i];
    if (t.role == 'assistant' && t.toolCalls.isNotEmpty) {
      for (final c in t.toolCalls) {
        steps.add(TaskStep.fromCall(
          call: c,
          result: results[c.id],
          live: live,
          actor: actor,
          runId: runId,
          turnIndex: turnIndex,
          transcriptIndex: transcriptOffset + i,
          ownerTsMs: t.tsMs,
        ));
      }
    }
  }
  return steps;
}

/// One turn of a session, as shown in the Timeline task list.
class SessionTask {
  final String runId;
  final int turnIndex;

  /// Transcript index of this task's first item (its user message).
  final int firstItemIndex;

  final String title;
  final SessionTaskStatus status;
  final int startedMs;
  final int updatedMs;

  /// Main-actor steps, in transcript order.
  final List<TaskStep> steps;

  /// Child run ids spawned by this task's delegate steps, in order of
  /// first delegation (ids stable by childRunId).
  final List<String> subagentRunIds;

  const SessionTask({
    required this.runId,
    required this.turnIndex,
    required this.firstItemIndex,
    required this.title,
    required this.status,
    required this.startedMs,
    required this.updatedMs,
    required this.steps,
    required this.subagentRunIds,
  });

  List<TaskStep> get delegateSteps => steps.where((s) => s.isDelegate).toList();

  /// Summary of the newest step (a running step preferentially), else
  /// the last step's summary, else ''. Callers hide the empty case.
  String get liveSummary {
    TaskStep? running;
    for (final s in steps) {
      if (s.status == TaskStepStatus.running) running = s;
    }
    final pick = running ?? (steps.isEmpty ? null : steps.last);
    return pick?.summary ?? '';
  }
}

/// Task title from a user message: first non-empty line,
/// whitespace-collapsed, truncated to ~60 chars.
String taskTitleFromText(String text) {
  for (final line in text.split('\n')) {
    final collapsed = line.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (collapsed.isNotEmpty) return truncateTo(collapsed, 60);
  }
  return '';
}

/// Segment a run's transcript into tasks (one per user message) and
/// derive each task's title, status, and steps.
List<SessionTask> sessionTasksForRun(PantheonRun run) {
  final items = run.transcript;
  if (items.isEmpty) return const [];

  // Segment boundaries: each user message starts a task. Items before
  // the first user message belong to the first task.
  final starts = <int>[];
  for (var i = 0; i < items.length; i++) {
    if (items[i].role == 'user') starts.add(i);
  }
  if (starts.isEmpty || starts.first != 0) starts.insert(0, 0);

  final live = isLiveRunStatus(run.status);
  final tasks = <SessionTask>[];
  for (var t = 0; t < starts.length; t++) {
    final start = starts[t];
    final end = t + 1 < starts.length ? starts[t + 1] : items.length;
    final segment = items.sublist(start, end);
    final isLast = t == starts.length - 1;

    final userItem = items[start].role == 'user' ? items[start] : null;
    var title = userItem == null ? '' : taskTitleFromText(userItem.content);
    if (title.isEmpty) {
      title = run.title.trim().isNotEmpty ? run.title.trim() : 'Task';
    }

    int? firstTs;
    int? lastTs;
    for (final it in segment) {
      if (it.tsMs != null) {
        firstTs ??= it.tsMs;
        lastTs = it.tsMs;
      }
    }
    final startedMs = (userItem?.tsMs ?? firstTs) ?? run.createdMs;
    final updatedMs = lastTs ?? (run.updatedMs > 0 ? run.updatedMs : startedMs);

    final SessionTaskStatus status;
    // This task's turn span, for attributing a run_failed event: the
    // event fails the turn it landed in, not every earlier turn.
    final nextStartMs = t + 1 < starts.length
        ? (items[starts[t + 1]].tsMs ?? (1 << 62))
        : (1 << 62);
    if (isLast && live) {
      status = SessionTaskStatus.inProgress;
    } else if ((isLast && run.status == 'failed') ||
        run.timeline.any((e) =>
            e.kind == 'run_failed' &&
            e.tsMs >= startedMs &&
            e.tsMs < nextStartMs)) {
      status = SessionTaskStatus.failed;
    } else {
      status = SessionTaskStatus.completed;
    }

    final steps = taskStepsFromItems(
      segment,
      live: live && isLast,
      actor: 'main',
      runId: run.id,
      turnIndex: t,
      transcriptOffset: start,
    );
    final subagents = <String>[];
    for (final s in steps) {
      final id = s.childRunId;
      if (s.isDelegate && id != null && !subagents.contains(id)) {
        subagents.add(id);
      }
    }

    tasks.add(SessionTask(
      runId: run.id,
      turnIndex: t,
      firstItemIndex: start,
      title: title,
      status: status,
      startedMs: startedMs,
      updatedMs: updatedMs,
      steps: steps,
      subagentRunIds: subagents,
    ));
  }
  return tasks;
}

/// One day's tasks in the task list.
class TaskDayGroup {
  final DateTime day;
  final List<SessionTask> tasks;
  const TaskDayGroup({required this.day, required this.tasks});
}

/// Group tasks by local calendar day of [SessionTask.startedMs],
/// newest day first, newest task first within a day.
List<TaskDayGroup> groupTasksByDay(List<SessionTask> tasks) {
  final sorted = [...tasks]..sort((a, b) => b.startedMs.compareTo(a.startedMs));
  final groups = <TaskDayGroup>[];
  for (final task in sorted) {
    final d = DateTime.fromMillisecondsSinceEpoch(task.startedMs);
    final day = DateTime(d.year, d.month, d.day);
    if (groups.isNotEmpty && groups.last.day == day) {
      groups.last.tasks.add(task);
    } else {
      groups.add(TaskDayGroup(day: day, tasks: [task]));
    }
  }
  return groups;
}
