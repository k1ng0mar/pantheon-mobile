import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pantheon_mobile/models/approval.dart';
import 'package:pantheon_mobile/widgets/approval_actions.dart';

Approval _approval(List<String>? tiers) => Approval.fromJson({
      'id': 'call-1:exec:rm -rf /',
      'run_id': 'run-1',
      'run_created_ms': 0,
      'tool': 'exec',
      if (tiers != null) 'available_tiers': tiers,
    });

void main() {
  group('Approval.fromJson available_tiers', () {
    test('parses the full tier set in backend order', () {
      final a = _approval(['once', 'session', 'always']);
      expect(a.availableTiers, ['once', 'session', 'always']);
    });

    test('parses a subset exactly as offered', () {
      final a = _approval(['once']);
      expect(a.availableTiers, ['once']);
    });

    test('absent available_tiers falls back to empty', () {
      final a = _approval(null);
      expect(a.availableTiers, isEmpty);
    });

    test('unknown tier strings are dropped, never rendered', () {
      final a = _approval(['once', 'someday', 'always']);
      expect(a.availableTiers, ['once', 'always']);
    });
  });

  group('StandingGrant.fromJson', () {
    test('parses the grants list payload', () {
      final g = StandingGrant.fromJson({
        'id': 3,
        'tool': 'exec',
        'args_preview': 'ls …',
        'created_ms': 42,
      });
      expect(g.id, 3);
      expect(g.tool, 'exec');
      expect(g.argsPreview, 'ls …');
      expect(g.createdMs, 42);
    });
  });

  group('ApprovalActions', () {
    Future<void> pumpActions(
      WidgetTester tester, {
      required List<String> tiers,
      required void Function() onDeny,
      required void Function(String?) onGrant,
    }) {
      return tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ApprovalActions(
            tiers: tiers,
            onDeny: onDeny,
            onGrant: onGrant,
          ),
        ),
      ));
    }

    testWidgets('renders exactly the offered subset', (tester) async {
      await pumpActions(tester,
          tiers: ['once', 'session'], onDeny: () {}, onGrant: (_) {});
      expect(find.text('Allow once'), findsOneWidget);
      expect(find.text('Approve session'), findsOneWidget);
      expect(find.text('Always allow'), findsNothing);
      expect(find.text('Grant'), findsNothing);
      expect(find.text('Deny'), findsOneWidget);
    });

    testWidgets('falls back to Deny/Grant when tiers are absent',
        (tester) async {
      await pumpActions(tester, tiers: [], onDeny: () {}, onGrant: (_) {});
      expect(find.text('Deny'), findsOneWidget);
      expect(find.text('Grant'), findsOneWidget);
      expect(find.text('Allow once'), findsNothing);
      expect(find.text('Approve session'), findsNothing);
      expect(find.text('Always allow'), findsNothing);
    });

    testWidgets('tier tap grants with the matching mode', (tester) async {
      String? mode;
      var denied = false;
      await pumpActions(tester,
          tiers: ['once', 'always'],
          onDeny: () => denied = true,
          onGrant: (m) => mode = m);
      await tester.tap(find.text('Always allow'));
      expect(mode, 'always');
      await tester.tap(find.text('Deny'));
      expect(denied, isTrue);
    });

    testWidgets('fallback Grant passes a null mode', (tester) async {
      String? mode = 'unset';
      await pumpActions(tester,
          tiers: [], onDeny: () {}, onGrant: (m) => mode = m);
      await tester.tap(find.text('Grant'));
      expect(mode, isNull);
    });
  });
}
