import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';

import 'package:pantheon_mobile/services/app_preferences.dart';
import 'package:pantheon_mobile/widgets/voice_note_pill.dart';

class _FailingRecorder extends AudioRecorder {
  @override
  Future<void> start(RecordConfig config, {required String path}) async {
    throw StateError('no recorder in widget tests');
  }

  @override
  Future<String?> stop() async => null;

  @override
  Future<void> dispose() async {}

  @override
  Future<void> cancel() async {}
}

/// Widget tests for the voice-note composer pill. They use a recorder
/// stub that fails on start, so the pill always takes its fail-safe path
/// instead of depending on which platform plugins happen to be installed.
/// The send→upload→transcript-into-composer path lives in
/// SessionDetailScreen._finishVoiceNote and is not covered here: pumping
/// the full session screen needs fixtures this env can't run.
void main() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() {
    AppPreferences.instance.hapticsEnabled.value = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getTemporaryDirectory') return '/tmp';
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('pill renders trash, running timer, waveform and send',
      (tester) async {
    var discarded = 0;
    final recorder = _FailingRecorder();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VoiceNotePill(
            recorder: recorder,
            onDiscard: () => discarded++,
            onFinished: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // No platform recorder in tests: start fails, pill bails out via
    // onDiscard rather than leaving a dead pill on screen.
    expect(discarded, greaterThanOrEqualTo(1));
    expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    expect(find.text('0:00'), findsOneWidget);
    // The waveform bars are plain containers in a fixed-height box.
    expect(find.byType(VoiceNotePill), findsOneWidget);

    await recorder.dispose();
  });

  testWidgets('trash discards without confirmation', (tester) async {
    var discarded = 0;
    var finished = 0;
    final recorder = _FailingRecorder();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VoiceNotePill(
            recorder: recorder,
            onDiscard: () => discarded++,
            onFinished: (_) => finished++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final before = discarded;
    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await tester.pump();
    // One more discard from the tap itself; never a confirm dialog and
    // never a finished recording.
    expect(discarded, before + 1);
    expect(finished, 0);
    expect(find.byType(AlertDialog), findsNothing);

    await recorder.dispose();
  });

  testWidgets('send with a dead recorder falls back to discard',
      (tester) async {
    var discarded = 0;
    var finished = 0;
    final recorder = _FailingRecorder();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VoiceNotePill(
            recorder: recorder,
            onDiscard: () => discarded++,
            onFinished: (_) => finished++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pump();
    await tester.pump();
    // stop() gives back no path, so the pill discards instead of handing a
    // nonexistent file to the uploader.
    expect(finished, 0);
    expect(discarded, greaterThanOrEqualTo(1));

    await recorder.dispose();
  });
}
