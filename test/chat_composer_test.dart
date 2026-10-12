/// Widget tests for the floating [ChatComposer].
///
/// These exercise the composer's presentation contract in isolation —
/// the owning screen keeps all behavior (send, stop, attachments,
/// voice notes, model picking) and passes it in as callbacks:
///
///   - the pill renders the field, attach, model/mode, mic and send
///   - the send button dims (but stays tappable-checkable) when the
///     composer is empty and becomes a stop button while live
///   - the hint keeps the single-line ellipsis contract for long
///     agent names
///   - the model/mode label hides when null and fires [onModelTap]
///   - [replacing] swaps field+toolbar inside the same pill chrome
///   - [above] renders staged rows above the pill
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pantheon_mobile/theme.dart';
import 'package:pantheon_mobile/widgets/chat_composer.dart';

Widget _harness({
  String agentName = 'Pantheon',
  bool composerEmpty = true,
  bool sending = false,
  bool live = false,
  String? modelModeLabel = 'Build · acme · atlas',
  Widget? above,
  Widget? replacing,
  VoidCallback? onSend,
  VoidCallback? onStop,
  VoidCallback? onAttach,
  VoidCallback? onMic,
  VoidCallback? onModelTap,
}) {
  final controller = TextEditingController();
  final focusNode = FocusNode();
  return MaterialApp(
    theme: pantheonTheme(Brightness.dark),
    home: Scaffold(
      body: ChatComposer(
        controller: controller,
        focusNode: focusNode,
        agentName: agentName,
        enabled: true,
        composerEmpty: composerEmpty,
        sending: sending,
        live: live,
        returnSends: false,
        reduceMotion: true,
        modelModeLabel: modelModeLabel,
        onSend: onSend ?? () {},
        onStop: onStop ?? () {},
        onStopLongPress: () {},
        onAttach: onAttach ?? () {},
        onMic: onMic ?? () {},
        onModelTap: onModelTap ?? () {},
        above: above,
        replacing: replacing,
      ),
    ),
  );
}

Widget _app(double w, double h, double scale, Widget child) {
  return MaterialApp(
    theme: pantheonTheme(Brightness.light),
    home: MediaQuery(
      data: MediaQueryData(
          size: Size(w, h), textScaler: TextScaler.linear(scale)),
      child: Scaffold(body: child),
    ),
  );
}

ChatComposer _composer({String? label}) {
  return ChatComposer(
    controller: TextEditingController(),
    focusNode: FocusNode(),
    agentName: 'An Extremely Verbose Agent Name That Will Not Fit On One Row',
    enabled: true,
    composerEmpty: true,
    sending: false,
    live: false,
    returnSends: false,
    reduceMotion: true,
    modelModeLabel: label ??
        'Build · some-very-long-provider-name · some-very-long-model-name-123',
    onSend: () {},
    onStop: () {},
    onStopLongPress: () {},
    onAttach: () {},
    onMic: () {},
    onModelTap: () {},
    above: const Text('staged attachment chip row'),
  );
}

void main() {
  testWidgets('pill renders field, attach, model/mode, mic and send',
      (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    expect(find.text('Build · acme · atlas'), findsOneWidget);
  });

  testWidgets('hint stays single-line with ellipsis for long agent names',
      (tester) async {
    const longName =
        'An Extremely Verbose Agent Name That Will Not Fit On One Composer Row';
    await tester.pumpWidget(_harness(agentName: longName));
    await tester.pumpAndSettle();

    final hintFinder = find.text('Message $longName…');
    expect(hintFinder, findsOneWidget);
    final hint = tester.widget<Text>(hintFinder);
    expect(hint.maxLines, 1);
    expect(hint.style?.overflow, TextOverflow.ellipsis);
  });

  testWidgets('typed text expands the field to multiple lines', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.minLines, 1);
    expect(field.maxLines, 5);

    await tester.enterText(find.byType(TextField), 'one\ntwo\nthree');
    await tester.pump();
    expect(find.text('one\ntwo\nthree'), findsOneWidget);
  });

  testWidgets('send dims when empty and fires onSend when tapped with text',
      (tester) async {
    var sent = 0;
    await tester
        .pumpWidget(_harness(composerEmpty: true, onSend: () => sent++));
    await tester.pumpAndSettle();

    // Dimmed, non-functional while empty.
    final opacity = tester.widget<AnimatedOpacity>(find.ancestor(
        of: find.byIcon(Icons.arrow_upward_rounded),
        matching: find.byType(AnimatedOpacity)));
    expect(opacity.opacity, 0.35);
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pump();
    expect(sent, 0);

    // With text, tapping sends.
    await tester
        .pumpWidget(_harness(composerEmpty: false, onSend: () => sent++));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pump();
    expect(sent, 1);
  });

  testWidgets('live turn morphs send into a stop button', (tester) async {
    var stopped = 0;
    await tester.pumpWidget(
        _harness(live: true, composerEmpty: true, onStop: () => stopped++));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward_rounded), findsNothing);
    await tester.tap(find.byIcon(Icons.stop_rounded));
    await tester.pump();
    expect(stopped, 1);
  });

  testWidgets('model/mode button hides when label is null', (tester) async {
    await tester.pumpWidget(_harness(modelModeLabel: null));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.expand_more_rounded), findsNothing);
  });

  testWidgets('model/mode button fires onModelTap', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(_harness(onModelTap: () => tapped++));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Build · acme · atlas'));
    await tester.pump();
    expect(tapped, 1);
  });

  testWidgets('attach and mic fire their callbacks', (tester) async {
    var attached = 0;
    var micced = 0;
    await tester.pumpWidget(
        _harness(onAttach: () => attached++, onMic: () => micced++));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pump();
    expect(attached, 1);
    await tester.tap(find.byIcon(Icons.mic_rounded));
    await tester.pump();
    expect(micced, 1);
  });

  testWidgets('replacing swaps field+toolbar inside the pill', (tester) async {
    await tester.pumpWidget(_harness(
      replacing: const Text('transcribing…'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('transcribing…'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byIcon(Icons.add_rounded), findsNothing);
  });

  testWidgets('above renders staged rows above the pill', (tester) async {
    await tester.pumpWidget(_harness(
      above: const Text('staged attachment'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('staged attachment'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    // The staged row sits above the field in paint order.
    final stagedY = tester.getTopLeft(find.text('staged attachment')).dy;
    final fieldY = tester.getTopLeft(find.byType(TextField)).dy;
    expect(stagedY, lessThan(fieldY));
  });

  testWidgets('narrow 320pt, long labels, no overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_app(320, 568, 1.0,
        Column(mainAxisSize: MainAxisSize.min, children: [_composer()])));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow 320pt + large text (1.3x), no overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_app(320, 568, 1.3,
        Column(mainAxisSize: MainAxisSize.min, children: [_composer()])));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('multiline growth at 320pt, no overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller =
        TextEditingController(text: 'line1\nline2\nline3\nline4\nline5\nline6');
    await tester.pumpWidget(_app(
        320,
        568,
        1.0,
        Column(mainAxisSize: MainAxisSize.min, children: [
          ChatComposer(
            controller: controller,
            focusNode: FocusNode(),
            agentName: 'Pantheon',
            enabled: true,
            composerEmpty: false,
            sending: false,
            live: false,
            returnSends: false,
            reduceMotion: true,
            modelModeLabel: 'Build · acme · atlas',
            onSend: () {},
            onStop: () {},
            onStopLongPress: () {},
            onAttach: () {},
            onMic: () {},
            onModelTap: () {},
          ),
        ])));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
