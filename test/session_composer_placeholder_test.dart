/// Widget tests for the session composer placeholder.
///
/// UNVERIFIED IN THIS ENV: no Flutter/Dart SDK is installed here, so these
/// tests were written but never run. They exercise the production
/// [sessionComposerDecoration] helper (the same decoration the session
/// screen's composer uses) with a deliberately over-long agent name:
///   - the hint/placeholder `Text` is a single line with an ellipsis
///     overflow,
///   - the editable [TextField] keeps minLines 1 / maxLines 5, so typed
///     text still expands to multiple lines.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pantheon_mobile/theme.dart';
import 'package:pantheon_mobile/widgets/session_composer.dart';

const _longName =
    'An Extremely Verbose Agent Name That Will Not Fit On One Composer Row';

Widget _composerHarness(String agentName) {
  return MaterialApp(
    theme: pantheonTheme(Brightness.dark),
    home: Scaffold(
      body: Builder(
        builder: (context) => TextField(
          minLines: 1,
          maxLines: 5,
          style: PT.body.copyWith(fontSize: 14),
          decoration:
              sessionComposerDecoration(context, agentName: agentName),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('placeholder truncates to a single line with an ellipsis',
      (tester) async {
    await tester.pumpWidget(_composerHarness(_longName));
    await tester.pumpAndSettle();

    final hintFinder = find.text('Message $_longName…');
    expect(hintFinder, findsOneWidget);

    final hint = tester.widget<Text>(hintFinder);
    expect(hint.maxLines, 1);
    expect(hint.style?.overflow, TextOverflow.ellipsis);

    // The ellipsis treatment must not restyle the Nyx hint look.
    final themeHint =
        pantheonTheme(Brightness.dark).inputDecorationTheme.hintStyle!;
    expect(hint.style?.fontFamily, themeHint.fontFamily);
    expect(hint.style?.fontSize, themeHint.fontSize);
    expect(hint.style?.color, themeHint.color);
  });

  testWidgets('typed text still expands to multiple lines', (tester) async {
    await tester.pumpWidget(_composerHarness(_longName));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.minLines, 1);
    expect(field.maxLines, 5);

    await tester.enterText(
        find.byType(TextField), 'first line\nsecond line');
    await tester.pump();

    final editable =
        tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.controller.text, 'first line\nsecond line');
    // Multi-line capacity is unchanged: the ellipsis only constrained
    // the placeholder, never the editable field.
    expect(editable.maxLines, 5);
  });
}
