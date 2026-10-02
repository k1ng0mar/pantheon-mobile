// Fixture-based unit tests for the Timeline task/step model.
//
// These exercise app-side derivation over contract-shaped PantheonRun
// JSON (the same shapes the backend sends): task segmentation by user
// message, status derivation, delegate ordering, day grouping, and
// the deterministic title/summary/detail templates. No backend, no
// widget tree.

import 'package:flutter_test/flutter_test.dart';
import 'package:pantheon_mobile/models/pantheon_run.dart';
import 'package:pantheon_mobile/models/task_step.dart';

ToolCallRef call(String name, String args, {String id = 'c1'}) =>
    ToolCallRef(id: id, name: name, arguments: args);

void main() {
  group('step title templates', () {
    test('read → Read <path>', () {
      expect(deriveStepTitle(call('read_file', '{"path":"/a/b.txt"}')),
          'Read /a/b.txt');
    });

    test('list tool name → Listed <dir>', () {
      expect(deriveStepTitle(call('list_directory', '{"dir":"/home/u"}')),
          'Listed /home/u');
    });

    test('exec ls → Listed <dir>', () {
      expect(deriveStepTitle(call('exec', '{"command":"ls -la /srv"}')),
          'Listed /srv');
    });

    test('delegate → Delegated <task>', () {
      expect(
          deriveStepTitle(
              call('delegate', '{"agent":"r","task":"survey sources"}')),
          'Delegated survey sources');
    });

    test('edit → Edited <path>, write → Wrote <path>', () {
      expect(deriveStepTitle(call('edit_file', '{"path":"/x.dart"}')),
          'Edited /x.dart');
      expect(deriveStepTitle(call('write_file', '{"path":"/x.dart"}')),
          'Wrote /x.dart');
    });

    test('command → Ran <command>', () {
      expect(deriveStepTitle(call('shell', '{"command":"git status"}')),
          'Ran git status');
    });

    test('file-search → Searched <pattern>', () {
      expect(deriveStepTitle(call('grep', '{"pattern":"TODO","path":"/repo"}')),
          'Searched TODO');
    });

    test('web-search → Searched web for <query>', () {
      expect(deriveStepTitle(call('web_search', '{"query":"kaduna rain"}')),
          'Searched web for kaduna rain');
    });

    test('fallback → human name + salient arg', () {
      expect(deriveStepTitle(call('memory_store', '{"message":"note this"}')),
          'Memory Store note this');
      expect(deriveStepTitle(call('memory_store', '{}')), 'Memory Store');
    });

    test('long command truncates at ~48 chars', () {
      final t = deriveStepTitle(call('shell', '{"command":"${'x' * 80}"}'));
      expect(t.startsWith('Ran '), isTrue);
      expect(t.endsWith('…'), isTrue);
      expect(t.length, lessThanOrEqualTo(4 + 48 + 1));
    });
  });

  group('step summary templates', () {
    test('first output line with duration fact, no exit duplication', () {
      final s = deriveStepSummary(
        call: call('exec', '{"command":"make"}'),
        result: TranscriptItem(
            type: 'message',
            role: 'tool',
            content: 'Exit code: 0\nbuild ok',
            toolCallId: 'c1'),
        status: TaskStepStatus.done,
        durationMs: 64,
      );
      expect(s, contains('64 ms'));
      expect(s, contains('Exit code: 0'));
      expect('Exit code'.allMatches(s).length, 1);
    });

    test('exit code later in output becomes a prefix fact', () {
      final s = deriveStepSummary(
        call: call('exec', '{"command":"make"}'),
        result: TranscriptItem(
            type: 'message',
            role: 'tool',
            content: 'compiling…\nExit code: 2',
            toolCallId: 'c1'),
        status: TaskStepStatus.error,
        durationMs: null,
      );
      expect(s, startsWith('Exit code 2'));
      expect(s, contains('compiling…'));
    });

    test('no output → salient argument text, never empty fabrication', () {
      final s = deriveStepSummary(
        call: call('exec', '{"command":"sleep 30"}'),
        result: null,
        status: TaskStepStatus.running,
        durationMs: null,
      );
      expect(s, 'sleep 30');
    });

    test('no output and no salient arg → empty (widget hides it)', () {
      final s = deriveStepSummary(
        call: call('ping', '{}'),
        result: null,
        status: TaskStepStatus.running,
        durationMs: null,
      );
      expect(s, isEmpty);
    });
  });

  group('step status rules', () {
    TaskStep stepFor({TranscriptItem? result, required bool live}) =>
        TaskStep.fromCall(
          call: call('exec', '{"command":"true"}'),
          result: result,
          live: live,
          actor: 'main',
          runId: 'r',
          turnIndex: 0,
          transcriptIndex: 0,
        );

    test('missing result on settled run is an error', () {
      expect(stepFor(live: false).status, TaskStepStatus.error);
    });

    test('missing result on live run is running', () {
      expect(stepFor(live: true).status, TaskStepStatus.running);
    });

    test('Error-prefixed result is an error', () {
      final s = stepFor(
        live: false,
        result: TranscriptItem(
            type: 'message', role: 'tool', content: 'Error: boom'),
      );
      expect(s.status, TaskStepStatus.error);
      expect(s.detail, contains('reported an error'));
    });

    test('detail states only recorded facts', () {
      final s = stepFor(
        live: false,
        result: TranscriptItem(
            type: 'message',
            role: 'tool',
            content: 'Exit code: 0\ndone',
            durationMs: 64),
      );
      expect(s.detail, contains('Ran the command: true.'));
      expect(s.detail, contains('exit code 0'));
      expect(s.detail, contains('64 ms'));
    });
  });

  group('task derivation from a contract-shaped run', () {
    final t0 = DateTime(2026, 9, 30, 9, 0).millisecondsSinceEpoch;
    final t1 = DateTime(2026, 10, 2, 9, 0).millisecondsSinceEpoch;

    Map<String, dynamic> fixture(String status) => {
          'id': 'run1',
          'status': status,
          'created_ms': t0,
          'title': 'Fallback title',
          'transcript': [
            {
              'type': 'message',
              'role': 'user',
              'content': 'First task please',
              'ts_ms': t0,
            },
            {
              'type': 'message',
              'role': 'assistant',
              'content': '',
              'ts_ms': t0 + 1000,
              'tool_calls': [
                {
                  'id': 'c1',
                  'name': 'read_file',
                  'arguments': '{"path":"/a.txt"}',
                  'started_ms': t0 + 1000,
                  'duration_ms': 50,
                }
              ],
            },
            {
              'type': 'message',
              'role': 'tool',
              'content': 'file body',
              'tool_call_id': 'c1',
              'ts_ms': t0 + 2000,
              'duration_ms': 50,
            },
            {
              'type': 'message',
              'role': 'assistant',
              'content': 'done',
              'ts_ms': t0 + 3000,
            },
            {
              'type': 'message',
              'role': 'user',
              'content': 'Second   task\n\nwith details',
              'ts_ms': t1,
            },
            {
              'type': 'message',
              'role': 'assistant',
              'content': '',
              'ts_ms': t1 + 1000,
              'tool_calls': [
                {
                  'id': 'c2',
                  'name': 'delegate',
                  'arguments': '{"agent":"researcher","task":"survey"}',
                  'child_run_id': 'child-1',
                },
                {
                  'id': 'c3',
                  'name': 'delegate',
                  'arguments': '{"task":"summarize"}',
                  'child_run_id': 'child-2',
                },
                {
                  'id': 'c4',
                  'name': 'delegate',
                  'arguments': '{"task":"more survey"}',
                  'child_run_id': 'child-1',
                },
              ],
            },
            {
              'type': 'message',
              'role': 'tool',
              'content': 'researched',
              'tool_call_id': 'c2',
              'ts_ms': t1 + 5000,
            },
            {
              'type': 'message',
              'role': 'tool',
              'content': 'summarized',
              'tool_call_id': 'c3',
              'ts_ms': t1 + 6000,
            },
            {
              'type': 'message',
              'role': 'tool',
              'content': 'more',
              'tool_call_id': 'c4',
              'ts_ms': t1 + 7000,
            },
          ],
        };

    test('segments by user message; titles collapse whitespace', () {
      final tasks =
          sessionTasksForRun(PantheonRun.fromJson(fixture('completed')));
      expect(tasks.length, 2);
      expect(tasks[0].title, 'First task please');
      expect(tasks[1].title, 'Second task');
      expect(tasks[0].turnIndex, 0);
      expect(tasks[1].turnIndex, 1);
      expect(tasks[0].runId, 'run1');
      expect(tasks[0].steps.length, 1);
      expect(tasks[0].steps.single.title, 'Read /a.txt');
      expect(tasks[0].steps.single.childRunId, isNull);
      expect(tasks[0].status, SessionTaskStatus.completed);
      expect(tasks[1].status, SessionTaskStatus.completed);
      expect(tasks[0].startedMs, t0);
      expect(tasks[1].startedMs, t1);
    });

    test('delegate grouping: first-delegation order, stable ids', () {
      final tasks =
          sessionTasksForRun(PantheonRun.fromJson(fixture('completed')));
      expect(tasks[1].subagentRunIds, ['child-1', 'child-2']);
      expect(tasks[1].delegateSteps.length, 3);
      expect(tasks[1].steps.every((s) => s.actor == 'main'), isTrue);
    });

    test('running run: last task in progress, earlier completed', () {
      final tasks =
          sessionTasksForRun(PantheonRun.fromJson(fixture('running')));
      expect(tasks[0].status, SessionTaskStatus.completed);
      expect(tasks[1].status, SessionTaskStatus.inProgress);
    });

    test('failed run: final task failed', () {
      final tasks = sessionTasksForRun(PantheonRun.fromJson(fixture('failed')));
      expect(tasks[0].status, SessionTaskStatus.completed);
      expect(tasks[1].status, SessionTaskStatus.failed);
    });

    test('run_failed timeline event after task start fails that task', () {
      final j = fixture('completed');
      j['timeline'] = [
        {'seq': 9, 'ts_ms': t1 + 9000, 'kind': 'run_failed', 'detail': 'boom'}
      ];
      final tasks = sessionTasksForRun(PantheonRun.fromJson(j));
      expect(tasks[1].status, SessionTaskStatus.failed);
      expect(tasks[0].status, SessionTaskStatus.completed);
    });

    test('liveSummary prefers the running step', () {
      final j = fixture('running');
      // Drop the c4 result so the last delegate call is still running.
      (j['transcript'] as List)
          .removeWhere((e) => e is Map && e['tool_call_id'] == 'c4');
      final tasks = sessionTasksForRun(PantheonRun.fromJson(j));
      final running = tasks[1].steps.last;
      expect(running.status, TaskStepStatus.running);
      expect(tasks[1].liveSummary, running.summary);
      expect(tasks[1].liveSummary, isNotEmpty);
    });

    test('empty user text falls back to run title, then Task', () {
      final j = fixture('completed');
      (j['transcript'] as List)[0] = {
        'type': 'message',
        'role': 'user',
        'content': '   \n  ',
        'ts_ms': t0,
      };
      var tasks = sessionTasksForRun(PantheonRun.fromJson(j));
      expect(tasks[0].title, 'Fallback title');
      j['title'] = '';
      tasks = sessionTasksForRun(PantheonRun.fromJson(j));
      expect(tasks[0].title, 'Task');
    });

    test('long task title truncates at ~60 chars', () {
      final title = taskTitleFromText('word ' * 30);
      expect(title.endsWith('…'), isTrue);
      expect(title.length, lessThanOrEqualTo(61));
    });

    test('empty transcript → no tasks', () {
      final tasks = sessionTasksForRun(PantheonRun.fromJson(
          {'id': 'r', 'status': 'completed', 'created_ms': 1, 'title': ''}));
      expect(tasks, isEmpty);
    });
  });

  group('day grouping', () {
    test('groups by local day, newest first', () {
      final t0 = DateTime(2026, 9, 30, 9, 0).millisecondsSinceEpoch;
      final t1 = DateTime(2026, 10, 2, 9, 0).millisecondsSinceEpoch;
      SessionTask task(int turn, int ms) => SessionTask(
            runId: 'r',
            turnIndex: turn,
            firstItemIndex: turn,
            title: 't$turn',
            status: SessionTaskStatus.completed,
            startedMs: ms,
            updatedMs: ms,
            steps: const [],
            subagentRunIds: const [],
          );
      final groups =
          groupTasksByDay([task(0, t0), task(1, t1), task(2, t1 + 60000)]);
      expect(groups.length, 2);
      expect(groups.first.day, DateTime(2026, 10, 2));
      expect(groups.first.tasks.length, 2);
      expect(groups.last.day, DateTime(2026, 9, 30));
      // Newest task first within the day.
      expect(groups.first.tasks.first.turnIndex, 2);
    });
  });
}
