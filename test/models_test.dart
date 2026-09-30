import 'package:flutter_test/flutter_test.dart';
import 'package:pantheon_mobile/models/approval.dart';
import 'package:pantheon_mobile/models/config_doc.dart';
import 'package:pantheon_mobile/models/env_key.dart';
import 'package:pantheon_mobile/models/idea.dart';
import 'package:pantheon_mobile/models/log_tail.dart';
import 'package:pantheon_mobile/models/mcp_server.dart';
import 'package:pantheon_mobile/models/memory_entry.dart';
import 'package:pantheon_mobile/models/overview.dart';
import 'package:pantheon_mobile/models/pantheon_run.dart';
import 'package:pantheon_mobile/models/plugin.dart';
import 'package:pantheon_mobile/models/scheduled_job.dart';
import 'package:pantheon_mobile/models/schedule_template.dart';
import 'package:pantheon_mobile/models/skill.dart';
import 'package:pantheon_mobile/models/usage_stats.dart';

void main() {
  scheduledJobTests();
  test('Overview parses dashboard shape', () {
    final o = Overview.fromJson({
      'runs': {
        'total': 12,
        'by_status': {'completed': 9, 'running': 3}
      },
      'last_24h': {'cost_usd': 1.235, 'tokens': 42000},
      'approvals_pending': 2,
      'schedule': {'total': 5, 'active': 4},
    });
    expect(o.totalRuns, 12);
    expect(o.byStatus['running'], 3);
    expect(o.cost24h, 1.235);
    expect(o.tokens24h, 42000);
    expect(o.approvalsPending, 2);
    expect(o.jobsActive, 4);
  });

  test('PantheonRun parses list item shape', () {
    final r = PantheonRun.fromJson({
      'id': 'abc123',
      'status': 'awaiting_approval',
      'created_ms': 1759000000000,
      'title': 'Morning brief',
      'model': 'opus',
      'provider': 'anthropic',
      'input_tokens': 1000,
      'output_tokens': 500,
      'cost_usd': 0.045,
      'turns': 4,
      'tool_calls': 7,
      'approvals_pending': 1,
    });
    expect(r.id, 'abc123');
    expect(r.displayTitle, 'Morning brief');
    expect(r.totalTokens, 1500);
  });

  test('PantheonRun falls back to id prefix when untitled', () {
    final r = PantheonRun.fromJson({
      'id': 'abcdef123456',
      'status': 'completed',
      'created_ms': 0,
      'title': '',
    });
    expect(r.displayTitle, 'abcdef12');
  });

  test('PantheonRun detects the pinned home session', () {
    final byFlag = PantheonRun.fromJson({
      'id': 'abc123',
      'status': 'completed',
      'created_ms': 0,
      'is_home': true,
    });
    expect(byFlag.pinned, true);
    final byAltFlag = PantheonRun.fromJson({
      'id': 'abc123',
      'status': 'completed',
      'created_ms': 0,
      'pinned': true,
    });
    expect(byAltFlag.pinned, true);
    final byId = PantheonRun.fromJson({
      'id': 'home',
      'status': 'completed',
      'created_ms': 0,
    });
    expect(byId.pinned, true);
    final plain = PantheonRun.fromJson({
      'id': 'abc123',
      'status': 'completed',
      'created_ms': 0,
    });
    expect(plain.pinned, false);
  });

  test('Idea parses ideas list shape', () {
    final i = Idea.fromJson({
      'id': 'idea_1',
      'title': 'Morning briefing',
      'description': 'A short digest of the day ahead.',
      'includes': ['Fetch calendar events', 'Summarize in three lines'],
      'kind': 'scheduled_task',
      'status': 'pending',
      'created_day': '2026-09-30',
      'schedule': {'type': 'cron', 'expr': '0 8 * * *'},
    });
    expect(i.title, 'Morning briefing');
    expect(i.kind, IdeaKind.scheduledTask);
    expect(i.includes, hasLength(2));
    expect(i.isPending, true);
    expect(i.schedule!['expr'], '0 8 * * *');
  });

  test('Idea tolerates a sparse payload', () {
    final i = Idea.fromJson({'id': 'idea_2'});
    expect(i.kind, IdeaKind.general);
    expect(i.status, 'pending');
    expect(i.includes, isEmpty);
    expect(i.schedule, isNull);
  });

  test('Approval parses queue item shape', () {
    final a = Approval.fromJson({
      'id': 'call_1:exec:{"cmd":"ls"}',
      'run_id': 'abc123',
      'run_title': 'Morning brief',
      'run_created_ms': 1759000000000,
      'call_id': 'call_1',
      'tool': 'exec',
      'args': '{"cmd":"ls"}',
    });
    expect(a.tool, 'exec');
    expect(a.displayRun, 'Morning brief');
  });

  test('UsageStats parses totals and sections', () {
    final s = UsageStats.fromJson({
      'totals': {
        'calls': 10,
        'input_tokens': 100,
        'output_tokens': 50,
        'total_tokens': 150,
        'cost_usd': 0.5
      },
      'by_model': {
        'opus': {
          'calls': 10,
          'input_tokens': 100,
          'output_tokens': 50,
          'total_tokens': 150,
          'cost_usd': 0.5
        }
      },
      'by_day': {},
    });
    expect(s.totals.calls, 10);
    expect(s.byModel['opus']!.costUsd, 0.5);
    expect(s.byDay, isEmpty);
  });

  test('Models tolerate missing fields', () {
    expect(() => Overview.fromJson({}), returnsNormally);
    expect(() => PantheonRun.fromJson({}), returnsNormally);
    expect(() => Approval.fromJson({}), returnsNormally);
    expect(() => UsageStats.fromJson({}), returnsNormally);
  });
}

void scheduledJobTests() {
  test('ScheduledJob parses kind object shapes', () {
    final cron = ScheduledJob.fromJson({
      'id': 'job_1',
      'task': 'morning brief',
      'kind': {'type': 'cron', 'expr': '0 9 * * *'},
      'paused': false,
      'last_run_ms': 1759090000000,
      'next_fire_ms': 1759200000000,
      'overlap': 'skip',
    });
    expect(cron.kind.type, 'cron');
    expect(cron.kind.display, '0 9 * * *');
    expect(cron.nextFireMs, 1759200000000);
    expect(cron.overlap, 'skip');

    final every = ScheduledJob.fromJson({
      'id': 'job_2',
      'task': 'check mail',
      'kind': {'type': 'every', 'every_ms': 3600000},
      'paused': true,
    });
    expect(every.kind.display, 'every 1h');
    expect(every.paused, isTrue);

    final manual = ScheduledJob.fromJson({
      'id': 'job_3',
      'task': 'adhoc',
      'kind': {'type': 'manual'},
      'paused': false,
    });
    expect(manual.kind.display, 'manual');
  });

  test('JobKind tolerates legacy string kind', () {
    final j = ScheduledJob.fromJson({
      'id': 'job_4',
      'task': 'x',
      'kind': 'cron',
      'paused': false,
    });
    expect(j.kind.type, 'cron');
  });

  test('MemoryEntry parses browse shape', () {
    final e = MemoryEntry.fromJson({
      'key': 'user.pref',
      'value': 'concise replies',
      'layer': 'agent',
      'namespace': 'agent:default',
      'provenance': {
        'source': 'chat',
        'origin': 'user',
        'trust': 'high'
      },
      'recorded_at_ms': 1759090000000,
      'score': null,
    });
    expect(e.key, 'user.pref');
    expect(e.provenanceSource, 'chat');
    expect(e.recordedAtMs, 1759090000000);
  });

  test('ConfigDoc exposes agents table', () {
    final d = ConfigDoc.fromJson({
      'path': '/data/config.toml',
      'values': {
        'model': {'provider': 'anthropic', 'model': 'opus'},
        'agents': {
          'atlas': {'display_name': 'Atlas', 'policy': 'coder'}
        },
      },
      'raw': '…',
    });
    expect(d.agents['atlas']!['policy'], 'coder');
  });

  test('EnvKey parses redacted shape', () {
    final k = EnvKey.fromJson({
      'key': 'OPENAI_API_KEY',
      'redacted': 'sk••••1234',
      'used_by': ['model.api_key_env'],
      'shadowed_by_process_env': false,
    });
    expect(k.redacted, 'sk••••1234');
    expect(k.usedBy, ['model.api_key_env']);
  });

  test('Skill parses list shape', () {
    final s = Skill.fromJson({
      'name': 'pdf',
      'description': 'read pdfs',
      'origin': 'bundled',
      'path': '/x',
      'enabled': false,
      'scope': 'pantheon',
    });
    expect(s.enabled, isFalse);
    expect(s.scope, 'pantheon');
  });

  test('McpServerGroup parses list shape', () {
    final g = McpServerGroup.fromJson({
      'source': 'pantheon',
      'origin': 'declaration',
      'servers': [
        {
          'name': 'fs',
          'transport': 'stdio',
          'command': 'npx',
          'args': ['-y', 'x'],
          'enabled': true,
          'readiness': 'ready',
          'approved': true,
        }
      ],
    });
    expect(g.servers.single.describe, 'npx -y x');
    expect(g.servers.single.readiness, 'ready');
  });

  test('Plugin parses list shape', () {
    final p = Plugin.fromJson({
      'kind': 'tool',
      'name': 'browser',
      'version': '0.2.0',
      'enabled': true,
      'bundled': false,
      'approved': false,
    });
    expect(p.kind, 'tool');
    expect(p.approved, isFalse);
  });

  test('ScheduleTemplate parses list shape', () {
    final t = ScheduleTemplate.fromJson({
      'name': 'brief',
      'description': 'daily brief',
      'schedule': {'type': 'cron', 'expr': '0 9 * * *'},
      'vars': [
        {'name': 'topic', 'default': 'news', 'reserved': false}
      ],
    });
    expect(t.scheduleDetail, '0 9 * * *');
    expect(t.vars.single.defaultValue, 'news');
  });

  test('LogTail parses tail shape', () {
    final l = LogTail.fromJson({
      'source': 'agent',
      'lines': ['a', 'b'],
    });
    expect(l.lines.length, 2);
    expect(l.note, isNull);
  });
}
