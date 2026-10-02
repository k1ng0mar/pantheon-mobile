/// Widget + parse tests for the P5a design-review app surface.
///
/// FIXTURE-BASED: these tests exercise fenced-block parsing, card/viewer
/// rendering, and action payload strings against a canned
/// `drafthouse-gate` block — they are NOT run against a live session or a
/// real backend. Still bytes come from a fake [PantheonApi] override.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pantheon_mobile/models/drafthouse_gate.dart';
import 'package:pantheon_mobile/screens/design_viewer_screen.dart';
import 'package:pantheon_mobile/services/pantheon_api.dart';
import 'package:pantheon_mobile/theme.dart';
import 'package:pantheon_mobile/widgets/design_review_card.dart';
import 'package:pantheon_mobile/widgets/design_review_shared.dart';
import 'package:pantheon_mobile/widgets/message_content.dart';

const _fixtureText = '''
Here's round 3 — the judge picked B.

```drafthouse-gate
{"artifact":"landing-v3.html","round":3,
 "variants":[{"id":"a","label":"Conservative","still":"up_a"},{"id":"b","label":"Strong-fit","still":"up_b"},{"id":"c","label":"Divergent","still":"up_c"}],
 "judge_pick":"b","judge_scores":{"a":3.4,"b":4.2,"c":3.8},
 "gate":{"p0":0,"p1":2,"p2":5,"five_dim":{"philosophy":4,"hierarchy":4,"execution":3,"specificity":5,"restraint":4},"tokens":"pass","vision":{"composite":8.4,"must_fix":[]}},
 "status":"needs_human"}
```

Let me know.
''';

const _shipText = '''
```drafthouse-gate
{"artifact":"pricing.html","round":5,
 "variants":[{"id":"a","label":"Only","still":"up_x"}],
 "judge_pick":"a","judge_scores":{"a":4.8},
 "gate":{"p0":0,"p1":0,"p2":1,"five_dim":{"philosophy":5,"hierarchy":5,"execution":5,"specificity":5,"restraint":5},"tokens":"pass","vision":null},
 "status":"ship"}
```
''';

/// 1x1 transparent PNG — decodable by the test engine.
final _pngBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==');

class _FakeApi extends PantheonApi {
  _FakeApi() : super(baseUrl: 'http://localhost', token: 'test');

  @override
  Future<List<int>> downloadUpload(String id) async => _pngBytes.toList();
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(
    theme: pantheonTheme(Brightness.dark),
    home: Scaffold(body: child),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => DesignStillCache.clearCacheForTest());

  group('parseFirst', () {
    test('parses the spec fixture exactly', () {
      final block = DrafthouseGateBlock.parseFirst(_fixtureText)!;
      expect(block.artifact, 'landing-v3.html');
      expect(block.round, 3);
      expect(block.variants.map((v) => v.id), ['a', 'b', 'c']);
      expect(block.variants[1].label, 'Strong-fit');
      expect(block.variants[1].still, 'up_b');
      expect(block.judgePick, 'b');
      expect(block.judgeScores['b'], 4.2);
      expect(block.gate.p0, 0);
      expect(block.gate.p1, 2);
      expect(block.gate.p2, 5);
      expect(block.gate.fiveDim['execution'], 3);
      expect(block.gate.tokens, 'pass');
      expect(block.gate.visionComposite, 8.4);
      expect(block.gate.mustFix, isEmpty);
      expect(block.status, 'needs_human');
      expect(block.needsHuman, isTrue);
    });

    test('no fence -> null', () {
      expect(DrafthouseGateBlock.parseFirst('no block here'), isNull);
    });

    test('malformed JSON -> null', () {
      expect(
        DrafthouseGateBlock.parseFirst(
            '```drafthouse-gate\n{not json}\n```'),
        isNull,
      );
    });

    test('incomplete JSON (missing gate) -> null', () {
      expect(
        DrafthouseGateBlock.parseFirst(
            '```drafthouse-gate\n{"artifact":"x","round":1}\n```'),
        isNull,
      );
    });

    test('block quoted inside an ordinary code fence is ignored', () {
      const quoted = '''
Here's the contract:

```
example:
```drafthouse-gate
{"artifact":"x"}
```
```
''';
      expect(DrafthouseGateBlock.parseFirst(quoted), isNull);
    });

    test('block quoted inside a longer ```` fence is ignored', () {
      const quoted = '''
Here's the contract:

````
```drafthouse-gate
{"artifact":"x"}
```
````
''';
      expect(DrafthouseGateBlock.parseFirst(quoted), isNull);
    });

    test('vision null keeps composite null; summary omits vision', () {
      final block = DrafthouseGateBlock.parseFirst(_shipText)!;
      expect(block.gate.visionComposite, isNull);
      expect(block.needsHuman, isFalse);
      expect(block.gateSummary(),
          'P0=0 · 5-dim min=5 · tokens=pass');
    });

    test('gate summary is the one-line spec string', () {
      final block = DrafthouseGateBlock.parseFirst(_fixtureText)!;
      expect(block.gateSummary(),
          'P0=0 · 5-dim min=3 · tokens=pass · vision 8.4');
    });

    test('picked variant falls back sensibly', () {
      final block = DrafthouseGateBlock.parseFirst(_fixtureText)!;
      expect(block.pickedVariant.id, 'b');
      expect(block.pickedIndex, 1);
    });

    test('MessageContent.firstGateBlock mirrors parseFirst', () {
      expect(MessageContent.firstGateBlock(_fixtureText), isNotNull);
      expect(MessageContent.firstGateBlock('plain text'), isNull);
    });
  });

  group('action payloads', () {
    test('approve message is the exact skill-contract trigger', () {
      expect(drafthouseApproveMessage(), 'Approved — proceed to handoff.');
    });

    test('request-changes message carries round, variant, text', () {
      expect(
        drafthouseRequestChangesMessage(3, 'b', 'Make the hero taller.'),
        'Round 3, variant b: Make the hero taller.',
      );
    });

    test('pick-variant message names the variant', () {
      expect(
        drafthousePickVariantMessage('c'),
        'Use variant c for the next round.',
      );
    });
  });

  group('card + viewer (fixture)', () {
    testWidgets('card renders title, summary, and pill from the block',
        (tester) async {
      final block = DrafthouseGateBlock.parseFirst(_fixtureText)!;
      await _pump(
          tester,
          DesignReviewCard(
              block: block, api: _FakeApi(), runId: 'run-1'));
      expect(find.text('Design · landing-v3.html · round 3'), findsOneWidget);
      expect(find.text('P0=0 · 5-dim min=3 · tokens=pass · vision 8.4'),
          findsOneWidget);
      expect(find.text('needs review'), findsOneWidget);
      // 16:9 thumbnail of the judge pick's still renders.
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('ship status renders the green pill', (tester) async {
      final block = DrafthouseGateBlock.parseFirst(_shipText)!;
      await _pump(
          tester, DesignReviewCard(block: block, api: _FakeApi(), runId: 'r'));
      expect(find.text('ship'), findsOneWidget);
      expect(find.text('needs review'), findsNothing);
    });

    testWidgets('tap opens the viewer', (tester) async {
      final block = DrafthouseGateBlock.parseFirst(_fixtureText)!;
      await _pump(
          tester,
          DesignReviewCard(
              block: block, api: _FakeApi(), runId: 'run-1'));
      await tester.tap(find.byType(DesignReviewCard));
      await tester.pumpAndSettle();
      expect(find.text('landing-v3.html · round 3'), findsWidgets);
    });

    testWidgets('MessageContent composes the card below the body',
        (tester) async {
      await _pump(
        tester,
        MessageContent(
          text: _fixtureText,
          textStyle: PT.body,
          api: _FakeApi(),
          runId: 'run-1',
        ),
      );
      expect(find.byType(DesignReviewCard), findsOneWidget);
    });

    testWidgets('MessageContent without runId renders no card',
        (tester) async {
      await _pump(
        tester,
        MessageContent(text: _fixtureText, textStyle: PT.body, api: _FakeApi()),
      );
      expect(find.byType(DesignReviewCard), findsNothing);
    });

    testWidgets('viewer shows all variants, judge pick marked',
        (tester) async {
      final block = DrafthouseGateBlock.parseFirst(_fixtureText)!;
      await _pump(
          tester,
          DesignViewerScreen(
              block: block, api: _FakeApi(), runId: 'run-1'));
      // Variant dots + labels for all three variants.
      expect(find.text('A · Conservative'), findsOneWidget);
      expect(find.text('B · Strong-fit'), findsOneWidget);
      expect(find.text('C · Divergent'), findsOneWidget);
      // Action bar.
      expect(find.text('Approve'), findsOneWidget);
      expect(find.text('Request changes'), findsOneWidget);
      expect(find.text('Pick variant'), findsOneWidget);
      expect(find.text('Gate report'), findsOneWidget);
    });

    testWidgets('viewer opens on the judge pick page', (tester) async {
      final block = DrafthouseGateBlock.parseFirst(_fixtureText)!;
      await _pump(
          tester,
          DesignViewerScreen(
              block: block, api: _FakeApi(), runId: 'run-1'));
      // Judge pick is B: no "differs from judge" confirm row on open.
      expect(find.textContaining('instead of the judge pick'), findsNothing);
    });

    testWidgets('gate report sheet shows dims, counts, tokens, vision',
        (tester) async {
      final block = DrafthouseGateBlock.parseFirst(_fixtureText)!;
      await _pump(
          tester,
          DesignViewerScreen(
              block: block, api: _FakeApi(), runId: 'run-1'));
      await tester.tap(find.text('Gate report'));
      await tester.pumpAndSettle();
      expect(find.text('Gate report · round 3'), findsOneWidget);
      expect(find.text('5-dimension scores'), findsOneWidget);
      expect(find.text('Philosophy'), findsOneWidget);
      expect(find.text('Execution · min'), findsOneWidget);
      expect(find.text('P0 blocking'), findsOneWidget);
      expect(find.text('Tokens'), findsOneWidget);
      expect(find.text('Vision composite'), findsOneWidget);
    });
  });
}
