/// Tests for the self-ticking live-turn clock.
///
/// Two contracts: the elapsed label format is pure and correct, and the
/// once-a-second tick repaints only the clock row, never its parent (the
/// transcript must not rebuild every second while a turn runs).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pantheon_mobile/widgets/live_clock.dart';

/// Parent that counts its own builds so the test can prove the clock tick
/// does not rebuild it.
class _Probe extends StatefulWidget {
  const _Probe({super.key});
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  int builds = 0;
  @override
  Widget build(BuildContext context) {
    builds++;
    return LiveClockRow(
      sinceMs: DateTime.now().millisecondsSinceEpoch - 5000,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('label format', () {
    test('seconds under a minute', () {
      expect(LiveClockRow.label(0), 'Working for 0s');
      expect(LiveClockRow.label(5), 'Working for 5s');
      expect(LiveClockRow.label(59), 'Working for 59s');
    });
    test('minutes and seconds', () {
      expect(LiveClockRow.label(60), 'Working for 1m 0s');
      expect(LiveClockRow.label(65), 'Working for 1m 5s');
      expect(LiveClockRow.label(125), 'Working for 2m 5s');
    });
    test('negative clamps to zero', () {
      expect(LiveClockRow.label(-3), 'Working for 0s');
    });
  });

  testWidgets('tick repaints the clock without rebuilding the parent',
      (tester) async {
    final probeKey = GlobalKey<_ProbeState>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: _Probe(key: probeKey)),
    ));
    expect(find.textContaining('Working for'), findsOneWidget);
    final buildsAfterFirstFrame = probeKey.currentState!.builds;

    // Advance two seconds: the periodic timer fires twice. Only the clock
    // row should rebuild; the parent build count must not move.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(probeKey.currentState!.builds, buildsAfterFirstFrame);

    // Dispose the row so its timer is cancelled before the test ends.
    await tester.pumpWidget(const SizedBox());
  });
}
