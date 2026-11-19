/// Tests for the counted truncation affordance on long code blocks.
///
/// A long block is previewed at a bounded height with a "Show all N
/// lines" footer; tapping expands to full height and offers Collapse.
/// Short blocks render in full with no footer. The remainder is always
/// named, never silently cut.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pantheon_mobile/services/app_preferences.dart';
import 'package:pantheon_mobile/theme.dart';
import 'package:pantheon_mobile/widgets/code_block.dart';

Widget _harness(String code) => MaterialApp(
      theme: pantheonTheme(Brightness.dark),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: CodeBlock(code: code, languageTag: ''),
          ),
        ),
      ),
    );

bool _bounded(WidgetTester tester) => tester
    .widgetList<ConstrainedBox>(find.byType(ConstrainedBox))
    .any((b) => b.constraints.maxHeight == 324);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppPreferences.instance.init();
  });

  testWidgets('long code is bounded and names its remainder', (tester) async {
    final code = List.generate(50, (i) => 'line $i').join('\n');
    await tester.pumpWidget(_harness(code));
    await tester.pump();

    expect(find.text('Show all 50 lines'), findsOneWidget);
    expect(_bounded(tester), isTrue);
  });

  testWidgets('expand reveals full code, collapse restores the preview',
      (tester) async {
    final code = List.generate(50, (i) => 'line $i').join('\n');
    await tester.pumpWidget(_harness(code));
    await tester.pump();

    await tester.ensureVisible(find.text('Show all 50 lines'));
    await tester.pump();
    await tester.tap(find.text('Show all 50 lines'));
    await tester.pump();
    expect(find.text('Collapse'), findsOneWidget);
    expect(find.text('Show all 50 lines'), findsNothing);
    expect(_bounded(tester), isFalse);

    // Expanding makes the block tall, so the footer scrolls out of view;
    // bring it back before tapping.
    await tester.ensureVisible(find.text('Collapse'));
    await tester.pump();
    await tester.tap(find.text('Collapse'));
    await tester.pump();
    expect(find.text('Show all 50 lines'), findsOneWidget);
  });

  testWidgets('short code renders in full with no footer', (tester) async {
    final code = List.generate(5, (i) => 'line $i').join('\n');
    await tester.pumpWidget(_harness(code));
    await tester.pump();
    expect(find.textContaining('Show all'), findsNothing);
    expect(find.text('Collapse'), findsNothing);
  });
}
