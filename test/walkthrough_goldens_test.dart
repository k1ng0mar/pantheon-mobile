/// Walkthrough screenshots as golden tests — CURRENTLY SKIPPED.
///
/// The box's browser cannot reach local servers (Meta-hardened Chromium
/// blocks local network access), so screenshots were attempted headlessly:
/// the real [SessionDetailScreen] pumped against the mock backend on
/// 127.0.0.1:7171 and captured with [matchesGoldenFile].
///
/// BLOCKED (verified 2026-10-01, Flutter 3.47.5) by two engine/test-harness
/// issues, each bisected with minimal probes:
/// 1. `FontLoader.load()` never completes under flutter_tester (hangs even
///    after pumpWidget + pumps, with valid TTFs) — screenshots would render
///    in the Ahem test font, which defeats their purpose.
/// 2. `TestWidgetsFlutterBinding` replaces HttpClient with a mock returning
///    400 for every request (documented in the failure output), so the real
///    mock backend is unreachable from widget tests. (Workaround exists:
///    `HttpOverrides.runZoned` with a real client — pointless until (1)
///    is fixed.)
///
/// Re-enable when either is fixed: set `skip: false` below and run
/// `flutter test --update-goldens test/walkthrough_goldens_test.dart`
/// with the mock backend running on 127.0.0.1:7171.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pantheon_mobile/screens/session_detail_screen.dart';
import 'package:pantheon_mobile/services/app_preferences.dart';
import 'package:pantheon_mobile/services/pantheon_api.dart';
import 'package:pantheon_mobile/theme.dart';

Future<void> _loadFonts() async {
  const fonts = {
    'SpaceGrotesk': 'assets/fonts/SpaceGrotesk.ttf',
    'Inter': 'assets/fonts/Inter.ttf',
    'JetBrainsMono': 'assets/fonts/JetBrainsMono.ttf',
  };
  for (final e in fonts.entries) {
    final bytes = await File(e.value).readAsBytes();
    final loader = FontLoader(e.key)
      ..addFont(Future.value(ByteData.view(bytes.buffer)));
    await loader.load();
  }
}

/// Pump the session detail screen and let its initial `_load()` (real
/// HTTP against the mock backend) finish.
Future<void> _pumpSession(
    WidgetTester tester, PantheonApi api, String runId) async {
  await tester.runAsync(() async {
    await tester.pumpWidget(MaterialApp(
      theme: pantheonTheme(Brightness.dark),
      home: SessionDetailScreen(api: api, runId: runId),
    ));
    // The mock answers instantly; 6s of pumped time is ample.
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  });
  await tester.pump();
}

void main() {
  testWidgets('walkthrough screenshots', skip: true, (tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await AppPreferences.instance.init();
    // No entrance animations in screenshots.
    AppPreferences.instance.reduceMotion.value = true;
    await _loadFonts();

    // 390x844 logical at 3x.
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api =
        PantheonApi(baseUrl: 'http://127.0.0.1:7171', token: 'walkthrough');

    // --- 1. Chat: table, code block, WRITING card, composer w/ model pill.
    await _pumpSession(tester, api, 'home');
    await tester.scrollUntilVisible(find.text('Rollout notes'), 600);
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/wt-chat-blocks.png'),
    );

    // --- 2. Interleaved Thoughts rows + the "1 agent used" pill.
    await tester.scrollUntilVisible(find.text('1 agent used'), -600);
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/wt-thoughts-pill.png'),
    );

    // --- 3. Subagents sheet, researcher expanded.
    await tester.tap(find.text('1 agent used'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('researcher'));
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/wt-subagents-sheet.png'),
    );

    // --- 4. In-flight sheet on the running session.
    await _pumpSession(tester, api, 'run_live');
    await tester.enterText(find.byType(TextField), 'use redis instead');
    await tester.pump(const Duration(milliseconds: 200));
    // AppBar stop icon comes first in tree order; the composer's is last.
    await tester.longPress(find.byIcon(Icons.stop_rounded).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/wt-inflight-sheet.png'),
    );
  });
}
