import 'package:flutter_test/flutter_test.dart';
import 'package:pantheon_mobile/models/approval.dart';
import 'package:pantheon_mobile/models/overview.dart';
import 'package:pantheon_mobile/models/pantheon_run.dart';
import 'package:pantheon_mobile/models/scheduled_job.dart';
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
}
