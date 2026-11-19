/// Regression test for the user-bubble width contract: a short message
/// must render a narrow bubble and a long message a wide one, not both
/// pinned to the same max width.
///
/// The bubble shrink-wraps its content with [IntrinsicWidth] under a
/// maxWidth cap. These tests exercise that mechanism against the real
/// [MessageContent] renderer (the same widget the session screen puts in
/// the bubble), so a regression that makes the content fill the cap again
/// fails here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pantheon_mobile/theme.dart';
import 'package:pantheon_mobile/widgets/message_content.dart';

/// The bubble structure the session screen uses for a user message:
/// right-aligned, capped at 85% of the screen, shrink-wrapped.
Widget _bubble(String text, {required double screenW}) {
  return MaterialApp(
    theme: pantheonTheme(Brightness.dark),
    home: Scaffold(
      body: Align(
        alignment: Alignment.centerRight,
        child: Container(
          key: const ValueKey('bubble'),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints: BoxConstraints(maxWidth: screenW * 0.85),
          decoration: BoxDecoration(
            gradient: P.gradient,
            borderRadius: BorderRadius.circular(18),
          ),
          child: IntrinsicWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MessageContent(
                  text: text,
                  textStyle: PT.body.copyWith(fontSize: 14, color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('short message renders a narrow bubble, long a wide one',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_bubble('hi', screenW: 390));
    await tester.pump();
    final shortW = tester.getSize(find.byKey(const ValueKey('bubble'))).width;

    await tester.pumpWidget(_bubble(
      'This is a much longer message that should wrap across several lines '
      'and push the bubble out toward its maximum width cap.',
      screenW: 390,
    ));
    await tester.pump();
    final longW = tester.getSize(find.byKey(const ValueKey('bubble'))).width;

    // The short bubble hugs its text; the long one grows toward the cap.
    expect(shortW, lessThan(longW));
    expect(shortW, lessThan(390 * 0.85));
    expect(longW, lessThanOrEqualTo(390 * 0.85 + 0.5));
  });
}
