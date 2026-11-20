/// Tests for the multi-source skill import sheet: the source picker
/// produces the right `POST /api/skills/import` payload for each source
/// (GitHub repo vs registry-scheme url), and empty input is rejected.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pantheon_mobile/theme.dart';
import 'package:pantheon_mobile/widgets/skill_import_sheet.dart';

class _Harness extends StatefulWidget {
  const _Harness({super.key});
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  SkillImportRequest? result;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            result = await showSkillImportSheet(context);
            if (mounted) setState(() {});
          },
          child: const Text('open'),
        ),
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('payload', () {
    test('registry schemes carry their prefix', () {
      expect(
        const SkillImportRequest(source: 'clawhub', value: 'my-skill').url,
        'clawhub:my-skill',
      );
      expect(
        const SkillImportRequest(source: 'hermes', value: 'skills/x/y').url,
        'hermes:skills/x/y',
      );
      expect(
        const SkillImportRequest(source: 'claude', value: 'document-skills/pdf')
            .url,
        'claude:document-skills/pdf',
      );
      expect(
        const SkillImportRequest(source: 'url', value: 'https://a/SKILL.md').url,
        'https://a/SKILL.md',
      );
    });
    test('repo is sent as a repo, not a url', () {
      const r = SkillImportRequest(source: 'repo', value: 'https://github.com/o/r');
      expect(r.isRepo, isTrue);
      expect(const SkillImportRequest(source: 'clawhub', value: 'x').isRepo,
          isFalse);
    });
    test('a local file is an upload, not a url or repo', () {
      const r = SkillImportRequest(
        source: 'file',
        value: 'my-skill.zip',
        fileBytes: [1, 2, 3],
      );
      expect(r.isFile, isTrue);
      expect(r.isRepo, isFalse);
      expect(r.fileBytes, [1, 2, 3]);
      expect(r.confirmBody, contains('my-skill.zip'));
    });
  });

  testWidgets('picker imports a ClawHub slug as clawhub:<slug>', (tester) async {
    final key = GlobalKey<_HarnessState>();
    await tester.pumpWidget(MaterialApp(
      theme: pantheonTheme(Brightness.dark),
      home: _Harness(key: key),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // All four sources are offered.
    for (final label in ['GitHub', 'ClawHub', 'Hermes', 'URL']) {
      expect(find.text(label), findsOneWidget);
    }

    await tester.tap(find.text('ClawHub'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'my-skill');
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();

    final r = key.currentState!.result;
    expect(r, isNotNull);
    expect(r!.source, 'clawhub');
    expect(r.value, 'my-skill');
    expect(r.url, 'clawhub:my-skill');
  });

  testWidgets('empty input is rejected, sheet stays open', (tester) async {
    final key = GlobalKey<_HarnessState>();
    await tester.pumpWidget(MaterialApp(
      theme: pantheonTheme(Brightness.dark),
      home: _Harness(key: key),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();

    expect(key.currentState!.result, isNull);
    expect(find.text('Import skill'), findsOneWidget);
  });
}
