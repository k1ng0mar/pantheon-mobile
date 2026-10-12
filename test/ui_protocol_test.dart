import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pantheon_mobile/models/models.dart';
import 'package:pantheon_mobile/widgets/ui_components.dart';

// Fixtures derived from the real Rust protocol wire format
// (pantheon-api/src/ui.rs): UiNode flattens its component, so JSON is
// {id, type, ...fields}.

Map<String, dynamic> _formDoc() => {
      'version': 1,
      'id': 'turn1-ui_0',
      'root': {
        'id': 'root',
        'type': 'form',
        'title': 'Deploy',
        'fields': [
          {
            'name': 'env',
            'label': 'Environment',
            'field_type': {
              'type': 'select',
              'options': ['staging', 'prod']
            },
            'required': true,
          },
          {
            'name': 'note',
            'label': 'Note',
            'field_type': {'type': 'text'},
          },
          {
            'name': 'token',
            'label': 'API token',
            'field_type': {'type': 'secret'},
            'required': true,
          },
          {
            'name': 'count',
            'label': 'Count',
            'field_type': {'type': 'number'},
          },
          {
            'name': 'dry',
            'label': 'Dry run',
            'field_type': {'type': 'boolean'},
            'default': 'true',
          },
          {
            'name': 'desc',
            'label': 'Description',
            'field_type': {'type': 'long_text'},
          },
        ],
        'submit': {
          'action_id': 'submit',
          'label': 'Deploy',
          'kind': {'kind': 'submit', 'tool': 'deploy'}
        },
      },
    };

Map<String, dynamic> _approvalDoc() => {
      'version': 1,
      'id': 'turn2-ui_0',
      'root': {
        'id': 'root',
        'type': 'approval',
        'title': 'Run migration?',
        'detail': 'This will alter the database.',
        'approve': {
          'action_id': 'approve',
          'label': 'Approve',
          'kind': {'kind': 'approval', 'decision': 'grant'}
        },
        'deny': {
          'action_id': 'deny',
          'label': 'Deny',
          'kind': {'kind': 'approval', 'decision': 'deny'}
        },
        'scope_hint': 'db:migrate',
      },
    };

void main() {
  group('UiDocument parsing', () {
    test('parses a form document', () {
      final doc = UiDocument.fromJson(_formDoc());
      expect(doc.version, 1);
      expect(doc.id, 'turn1-ui_0');
      expect(doc.isSupported, isTrue);
      final form = doc.root.component as UiForm;
      expect(form.fields, hasLength(6));
      expect(form.fields[0].fieldType, UiFieldType.select);
      expect(form.fields[0].options, ['staging', 'prod']);
      expect(form.fields[0].required, isTrue);
      expect(form.fields[2].fieldType, UiFieldType.secret);
      expect(form.fields[3].fieldType, UiFieldType.number);
      expect(form.fields[4].fieldType, UiFieldType.boolean);
      expect(form.fields[5].fieldType, UiFieldType.longText);
      expect(form.submit.actionId, 'submit');
      expect(form.submit.kind.tag, UiActionKindTag.submit);
    });

    test('parses an approval document', () {
      final doc = UiDocument.fromJson(_approvalDoc());
      final card = doc.root.component as UiApproval;
      expect(card.title, 'Run migration?');
      expect(card.approve.kind.tag, UiActionKindTag.approval);
      expect(card.deny.kind.tag, UiActionKindTag.approval);
      expect(card.scopeHint, 'db:migrate');
    });

    test('unknown component type degrades to UiUnsupported', () {
      final doc = UiDocument.fromJson({
        'version': 1,
        'id': 'x',
        'root': {'id': 'r', 'type': 'hologram', 'foo': 1},
      });
      expect(doc.root.component, isA<UiUnsupported>());
      expect((doc.root.component as UiUnsupported).type, 'hologram');
    });

    test('unsupported version degrades to explanatory note', () {
      final raw = _formDoc()..['version'] = 99;
      final doc = UiDocument.fromJson(raw);
      expect(doc.isSupported, isFalse);
      final degraded =
          UiDocument.unsupportedVersion(doc.id, doc.version);
      final md = degraded.root.component as UiMarkdown;
      expect(md.text, contains('v99'));
      expect(md.text, contains('v1'));
    });

    test('malformed document never throws', () {
      for (final bad in [
        <String, dynamic>{},
        {'version': 'x', 'id': 1, 'root': null},
        {'version': 1, 'id': 'x', 'root': {'id': 5}},
        {'version': 1, 'id': 'x', 'root': {'id': 'r'}},
      ]) {
        expect(() => UiDocument.fromJson(bad), returnsNormally);
      }
    });

    test('deeply nested input degrades instead of overflowing', () {
      Map<String, dynamic> deep(int n) => {
            'id': 'n$n',
            'type': 'layout',
            'kind': 'stack',
            'children': n <= 0
                ? [
                    {'id': 'leaf', 'type': 'markdown', 'text': 'x'}
                  ]
                : [deep(n - 1)],
          };
      final doc = UiDocument.fromJson({
        'version': 1,
        'id': 'x',
        'root': deep(50),
      });
      // Walk down; at depth 9 the node must be UiUnsupported('too-deep').
      UiNode node = doc.root;
      var sawTooDeep = false;
      for (var i = 0; i < 50; i++) {
        final c = node.component;
        if (c is UiUnsupported) {
          expect(c.type, 'too-deep');
          sawTooDeep = true;
          break;
        }
        node = (c as UiLayout).children.first;
      }
      expect(sawTooDeep, isTrue);
    });

    test('malformed nested structures degrade safely', () {
      final doc = UiDocument.fromJson({
        'version': 1,
        'id': 'x',
        'root': {
          'id': 'r',
          'type': 'layout',
          'kind': 'stack',
          'children': [
            {'id': 'a', 'type': 'details', 'summary': 's'}, // no body
            {'id': 'b', 'type': 'layout'}, // no children
            'not-a-map',
            42,
          ],
        },
      });
      final layout = doc.root.component as UiLayout;
      // Non-map children are dropped; missing sub-objects become empty.
      expect(layout.children, hasLength(2));
      final details = layout.children[0].component as UiDetails;
      expect(details.body.component, isA<UiUnsupported>());
    });

    test('layout recurses into children', () {
      final doc = UiDocument.fromJson({
        'version': 1,
        'id': 'x',
        'root': {
          'id': 'r',
          'type': 'layout',
          'kind': 'stack',
          'children': [
            {'id': 'a', 'type': 'markdown', 'text': 'hi'},
            {
              'id': 'b',
              'type': 'details',
              'summary': 'more',
              'body': {'id': 'b1', 'type': 'markdown', 'text': 'deep'}
            },
          ],
        },
      });
      final layout = doc.root.component as UiLayout;
      expect(layout.children, hasLength(2));
      final details = layout.children[1].component as UiDetails;
      expect((details.body.component as UiMarkdown).text, 'deep');
    });

    test('custom renders its fallback', () {
      final doc = UiDocument.fromJson({
        'version': 1,
        'id': 'x',
        'root': {
          'id': 'r',
          'type': 'custom',
          'name': 'fancy',
          'fallback': {'id': 'f', 'type': 'markdown', 'text': 'plain'}
        },
      });
      final custom = doc.root.component as UiCustom;
      expect((custom.fallback.component as UiMarkdown).text, 'plain');
    });
  });

  group('TranscriptItem UI integration', () {
    test('ui transcript item carries document and revision', () {
      final item = TranscriptItem.fromJson({
        'type': 'ui',
        'ui_id': 'turn1-ui_0',
        'revision': 3,
        'document': _formDoc(),
      });
      expect(item.isUi, isTrue);
      expect(item.uiId, 'turn1-ui_0');
      expect(item.uiRevision, 3);
      expect(item.uiDocument, isNotNull);
      expect(item.uiDocument!.id, 'turn1-ui_0');
    });

    test('message items are unaffected', () {
      final item = TranscriptItem.fromJson({
        'type': 'message',
        'role': 'assistant',
        'content': 'hello',
      });
      expect(item.isUi, isFalse);
      expect(item.uiDocument, isNull);
      expect(item.content, 'hello');
    });

    test('ui item with malformed document degrades, not crash', () {
      final item = TranscriptItem.fromJson({
        'type': 'ui',
        'ui_id': 'x',
        'revision': 1,
        'document': {'version': 1},
      });
      expect(item.isUi, isTrue);
      expect(item.uiDocument!.root.component, isA<UiMarkdown>());
    });

    test('ui item with unsupported version shows version note', () {
      final raw = _formDoc()..['version'] = 7;
      final item = TranscriptItem.fromJson({
        'type': 'ui',
        'ui_id': 'x',
        'revision': 1,
        'document': raw,
      });
      expect(item.isUi, isTrue);
      final md = item.uiDocument!.root.component as UiMarkdown;
      expect(md.text, contains('v7'));
    });
  });

  group('UiActionSubmission payload', () {
    test('serializes the exact wire schema', () {
      final sub = UiActionSubmission(
        uiId: 'turn1-ui_0',
        revision: 3,
        nodeId: 'root',
        actionId: 'submit',
        params: {'env': 'prod', 'dry': true, 'count': 2},
        nonce: 'm-123-1-ab',
      );
      expect(sub.toJson(), {
        'ui_id': 'turn1-ui_0',
        'revision': 3,
        'node_id': 'root',
        'action_id': 'submit',
        'params': {'env': 'prod', 'dry': true, 'count': 2},
        'nonce': 'm-123-1-ab',
      });
    });
  });

  group('UiFormView widget', () {
    UiForm formOf() =>
        (UiDocument.fromJson(_formDoc()).root.component as UiForm);

    Future<UiSubmitResult> okHandler(UiActionSubmission s) async =>
        UiSubmitResult.executed('ok');

    testWidgets('renders all field types', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: UiFormView(
            nodeId: 'root',
            form: formOf(),
            uiId: 'turn1-ui_0',
            revision: 1,
            onAction: okHandler,
          ),
        ),
      ));
      expect(find.text('Environment *'), findsOneWidget);
      expect(find.text('API token *'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Deploy'), findsOneWidget);
      // Secret field is obscured: find the inner TextField.
      final secret = tester.widget<TextField>(
        find.descendant(
          of: find.widgetWithText(TextFormField, 'API token *'),
          matching: find.byType(TextField),
        ),
      );
      expect(secret.obscureText, isTrue);
    });

    testWidgets('required validation blocks submission', (tester) async {
      var called = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: UiFormView(
            nodeId: 'root',
            form: formOf(),
            uiId: 'turn1-ui_0',
            revision: 1,
            onAction: (s) async {
              called = true;
              return UiSubmitResult.executed('ok');
            },
          ),
        ),
      ));
      await tester.tap(find.widgetWithText(FilledButton, 'Deploy'));
      await tester.pump();
      expect(called, isFalse);
      expect(find.text('Required'), findsWidgets);
    });

    testWidgets('submits typed params with pinned revision', (tester) async {
      UiActionSubmission? got;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: UiFormView(
              nodeId: 'root',
              form: formOf(),
              uiId: 'turn1-ui_0',
              revision: 4,
              onAction: (s) async {
                got = s;
                return UiSubmitResult.executed('done');
              },
            ),
          ),
        ),
      ));
      // Fill required fields: select env + secret token.
      await tester.tap(find.text('staging'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('prod').last);
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextFormField, 'API token *'), 's3cr3t');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Count'), '3');
      await tester.tap(find.widgetWithText(FilledButton, 'Deploy'));
      await tester.pumpAndSettle();
      expect(got, isNotNull);
      expect(got!.uiId, 'turn1-ui_0');
      expect(got!.revision, 4); // the displayed revision, pinned
      expect(got!.nodeId, 'root');
      expect(got!.actionId, 'submit');
      expect(got!.params['env'], 'prod');
      expect(got!.params['token'], 's3cr3t');
      expect(got!.params['count'], 3); // numeric, not string
      expect(got!.params['dry'], isTrue); // boolean default
      expect(got!.nonce, isNotEmpty);
      expect(find.textContaining('Done'), findsOneWidget);
    });

    testWidgets('stale outcome shows refresh message', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: UiFormView(
            nodeId: 'root',
            form: formOf(),
            uiId: 'turn1-ui_0',
            revision: 1,
            onAction: (s) async =>
                UiSubmitResult.stale('superseded'),
          ),
        ),
      ));
      await tester.tap(find.text('staging'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('prod').last);
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextFormField, 'API token *'), 'x');
      await tester.tap(find.widgetWithText(FilledButton, 'Deploy'));
      await tester.pumpAndSettle();
      expect(find.textContaining('updated'), findsOneWidget);
    });

    testWidgets('revision change resets form input and state',
        (tester) async {
      // Build at revision 1, fill a field, then rebuild the same
      // widget at revision 2 (as a transcript poll would). The old
      // input must not leak into the new revision's submission.
      UiActionSubmission? got;
      Widget build(int rev) => MaterialApp(
            home: Scaffold(
              body: UiFormView(
                key: const ValueKey('form'),
                nodeId: 'root',
                form: formOf(),
                uiId: 'turn1-ui_0',
                revision: rev,
                onAction: (s) async {
                  got = s;
                  return UiSubmitResult.executed('ok');
                },
              ),
            ),
          );
      await tester.pumpWidget(build(1));
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Note'), 'old value');
      await tester.pumpWidget(build(2));
      await tester.pump();
      // The old text is gone after the revision change.
      expect(
          tester
              .widget<TextFormField>(
                  find.widgetWithText(TextFormField, 'Note'))
              .controller!
              .text,
          isEmpty);
      // Fill required fields at the new revision and submit: the
      // submission must pin revision 2, not the old revision 1.
      await tester.tap(find.text('staging'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('prod').last);
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextFormField, 'API token *'), 'y');
      await tester.tap(find.widgetWithText(FilledButton, 'Deploy'));
      await tester.pumpAndSettle();
      expect(got, isNotNull);
      expect(got!.revision, 2);
      expect(got!.params['note'], isNull); // old value did not leak
    });
  });

  group('UiApprovalView widget', () {
    UiApproval approvalOf() =>
        (UiDocument.fromJson(_approvalDoc()).root.component as UiApproval);

    testWidgets('approve sends approval action, disables after',
        (tester) async {
      UiActionSubmission? got;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: UiApprovalView(
            nodeId: 'root',
            approval: approvalOf(),
            uiId: 'turn2-ui_0',
            revision: 2,
            onAction: (s) async {
              got = s;
              return UiSubmitResult.decided(true);
            },
          ),
        ),
      ));
      expect(find.text('Run migration?'), findsOneWidget);
      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();
      expect(got, isNotNull);
      expect(got!.actionId, 'approve');
      expect(got!.revision, 2);
      expect(got!.params, isEmpty);
      expect(find.textContaining('Approved'), findsOneWidget);
      // Decided cards stay decided: button disabled now.
      final btn = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(btn.onPressed, isNull);
    });

    testWidgets('deny sends deny action', (tester) async {
      UiActionSubmission? got;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: UiApprovalView(
            nodeId: 'root',
            approval: approvalOf(),
            uiId: 'turn2-ui_0',
            revision: 2,
            onAction: (s) async {
              got = s;
              return UiSubmitResult.decided(false);
            },
          ),
        ),
      ));
      await tester.tap(find.text('Deny'));
      await tester.pumpAndSettle();
      expect(got!.actionId, 'deny');
      expect(find.text('Denied'), findsOneWidget);
    });

    testWidgets('timeout retry reuses the same nonce', (tester) async {
      // An uncertain outcome must not mint a fresh nonce on retry:
      // the server's replay protection keys on the nonce.
      final nonces = <String>[];
      var attempt = 0;
      Widget build() => MaterialApp(
            home: Scaffold(
              body: UiApprovalView(
                key: const ValueKey('appr'),
                nodeId: 'root',
                approval: approvalOf(),
                uiId: 'turn2-ui_0',
                revision: 2,
                onAction: (s) async {
                  nonces.add(s.nonce);
                  attempt++;
                  if (attempt == 1) {
                    return UiSubmitResult.error(
                        'Connection timed out — the action may have run. '
                        'Watch the chat for the result.',
                        null);
                  }
                  return UiSubmitResult.decided(true);
                },
              ),
            ),
          );
      await tester.pumpWidget(build());
      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();
      expect(nonces, hasLength(1));
      // The error state allows a retry (not decided, not submitting).
      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();
      expect(nonces, hasLength(2));
      expect(nonces[0], nonces[1],
          reason: 'retry must reuse the nonce');
      expect(find.textContaining('Approved'), findsOneWidget);
    });
  });

  group('fallback rendering', () {
    testWidgets('unsupported component shows safe note', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: UiNodeView(
            node: UiNode(
                id: 'r', component: UiUnsupported(type: 'hologram')),
            uiId: 'x',
            revision: 1,
            onAction: _never,
          ),
        ),
      ));
      expect(find.textContaining('Unsupported content (hologram)'),
          findsOneWidget);
    });

    testWidgets('chart shows values without chart dependency',
        (tester) async {
      final node = UiNode.fromJson({
        'id': 'r',
        'type': 'chart',
        'chart_type': 'bar',
        'labels': ['a', 'b'],
        'series': [
          {'name': 's', 'values': [1, 2.5]}
        ],
      });
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: UiNodeView(
              node: node, uiId: 'x', revision: 1, onAction: _never),
        ),
      ));
      expect(find.text('a'), findsOneWidget);
      expect(find.text('2.50'), findsOneWidget);
    });
  });
}

Future<UiSubmitResult> _never(UiActionSubmission s) async =>
    UiSubmitResult.error('no', null);
