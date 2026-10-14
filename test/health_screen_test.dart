import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pantheon_mobile/models/health.dart';
import 'package:pantheon_mobile/screens/health_screen.dart';
import 'package:pantheon_mobile/services/pantheon_api.dart';
import 'package:pantheon_mobile/theme.dart';
import 'package:pantheon_mobile/widgets/pantheon_card.dart';

/// Sample `pantheon.health/v1` payload: degraded overall, one healthy
/// subsystem, one needing review, one unknown, two issues.
const _sampleJson = '''
{
  "schema": "pantheon.health/v1",
  "generated_at": "2026-10-14T11:00:00Z",
  "overall": "degraded",
  "summary": "Core runtime is functional. One provider credential is missing.",
  "core_runtime": {"status": "healthy", "label": "Healthy"},
  "issue_count": 2,
  "subsystems": [
    {"id": "runtime", "title": "Runtime & execution",
     "subtitle": "Engine, lifecycle, recovery", "status": "healthy",
     "checks": [{"id": "runtime.gateway", "status": "passed",
       "severity": "info", "summary": "Gateway service is running"}]},
    {"id": "providers", "title": "Models & providers",
     "subtitle": "Authentication, connectivity, routing", "status": "review",
     "checks": [
       {"id": "providers.default.key", "status": "failed", "severity": "warning",
        "summary": "Default: credential OPENAI_API_KEY is not configured",
        "details": "The Default model slot expects \$OPENAI_API_KEY.",
        "impact": "Requests through openai may fail.",
        "remediation": "Add OPENAI_API_KEY under More → Keys.",
        "duration_ns": 1200000},
       {"id": "providers.auth_probe", "status": "skipped", "severity": "info",
        "summary": "Live authentication probe requires a newer dashboard."}]},
    {"id": "memory", "title": "Memory & storage",
     "subtitle": "SQLite, migrations, retrieval", "status": "unknown",
     "checks": []}
  ],
  "issues": [
    {"id": "providers.default.key", "subsystem": "providers",
     "severity": "warning", "title": "Provider credential missing",
     "detail": "The Default model slot expects \$OPENAI_API_KEY, which is not configured.",
     "hint": "Add it under More → Keys."},
    {"id": "security.approvals", "subsystem": "security",
     "severity": "info", "title": "Approvals waiting",
     "detail": "2 approvals are waiting for your decision.",
     "hint": "Review them under More → Approvals."}
  ]
}
''';

class _FakeApi extends PantheonApi {
  _FakeApi() : super(baseUrl: 'http://localhost', token: 'test');

  @override
  Future<HealthReport> healthReport() async =>
      HealthReport.fromJson(jsonDecode(_sampleJson) as Map<String, dynamic>);
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(
    theme: pantheonTheme(Brightness.dark),
    home: Scaffold(body: child),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('HealthReport.fromJson', () {
    test('parses the sample contract exactly', () {
      final r = HealthReport.fromJson(
          jsonDecode(_sampleJson) as Map<String, dynamic>);
      expect(r.schema, 'pantheon.health/v1');
      expect(r.overall, HealthStatus.review); // degraded folds to review
      expect(r.summary, contains('Core runtime is functional'));
      expect(r.coreRuntimeStatus, HealthStatus.healthy);
      expect(r.coreRuntimeLabel, 'Healthy');
      expect(r.issueCount, 2);
      expect(r.subsystems.length, 3);
      expect(r.subsystems[1].status, HealthStatus.review);
      expect(r.subsystems[1].checks[0].failed, isTrue);
      expect(r.subsystems[1].checks[0].durationMs, 1.2);
      expect(r.subsystems[2].status, HealthStatus.unknown);
      expect(r.issues[0].severity, 'warning');
      expect(r.issues[0].title, 'Provider credential missing');
    });

    test('never throws on partial data', () {
      final r = HealthReport.fromJson({});
      expect(r.overall, HealthStatus.unknown);
      expect(r.summary, isEmpty);
      expect(r.coreRuntimeLabel, 'Unknown');
      expect(r.issueCount, 0);
      expect(r.subsystems, isEmpty);
      expect(r.issues, isEmpty);

      final s = SubsystemHealth.fromJson({'id': 'runtime'});
      expect(s.status, HealthStatus.unknown);
      expect(s.title, 'runtime');
      expect(s.checks, isEmpty);

      final c = HealthCheck.fromJson({'summary': 'x'});
      expect(c.status, 'skipped');
      expect(c.severity, 'info');
      expect(c.passed, isFalse);
    });
  });

  testWidgets('health screen renders header, issues and subsystems',
      (tester) async {
    await _pump(tester, HealthScreen(api: _FakeApi()));

    // Status header.
    expect(find.text('System status'), findsOneWidget);
    expect(find.text('Degraded'), findsOneWidget);
    expect(find.textContaining('Core runtime is functional'), findsOneWidget);

    // Stat cards.
    expect(find.text('CORE RUNTIME'), findsOneWidget);
    expect(find.text('Healthy'), findsOneWidget); // core-runtime stat card
    expect(find.text('ISSUES'), findsOneWidget);
    expect(find.text('2 found'), findsOneWidget);

    // Needs attention.
    expect(find.text('Needs attention'), findsOneWidget);
    expect(find.text('Provider credential missing'), findsOneWidget);
    expect(find.text('Approvals waiting'), findsOneWidget);

    // Subsystems list with status words (below the fold: scroll first).
    await tester.scrollUntilVisible(find.text('Models & providers'), 300);
    await tester.pumpAndSettle();
    expect(find.text('Subsystems'), findsOneWidget);
    expect(find.text('Runtime & execution'), findsOneWidget);
    expect(find.text('Models & providers'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(PRowCard), matching: find.text('Healthy')),
        findsOneWidget); // runtime subsystem row
    expect(find.text('Review'), findsOneWidget);
    expect(find.text('Unknown'), findsOneWidget);
  });

  testWidgets('tapping a subsystem opens its check drill-down',
      (tester) async {
    await _pump(tester, HealthScreen(api: _FakeApi()));

    await tester.scrollUntilVisible(find.text('Models & providers'), 300);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Models & providers'));
    await tester.pumpAndSettle();

    expect(
        find.text(
            'Default: credential OPENAI_API_KEY is not configured'),
        findsOneWidget);
    expect(
        find.text('Live authentication probe requires a newer dashboard.'),
        findsOneWidget);

    // Expanding the failed check reveals remediation.
    await tester.tap(find.text(
        'Default: credential OPENAI_API_KEY is not configured'));
    await tester.pumpAndSettle();
    expect(find.text('Add OPENAI_API_KEY under More → Keys.'),
        findsOneWidget);
  });
}
