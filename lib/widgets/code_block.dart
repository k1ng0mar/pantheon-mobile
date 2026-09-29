import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_preferences.dart';
import '../services/code_highlight.dart';
import '../theme.dart';
import 'forms.dart';

/// A fenced code block from chat: theme-colored surface, a header with
/// the language label and a copy button, and the highlighted code in
/// JetBrains Mono. The theme follows the Appearance "Code blocks" choice
/// (each theme carries its own background, so the block reads correctly
/// in either app brightness).
class CodeBlock extends StatelessWidget {
  final String code;
  final String languageTag;

  const CodeBlock({super.key, required this.code, required this.languageTag});

  @override
  Widget build(BuildContext context) {
    final prefs = AppPreferences.instance;
    return ValueListenableBuilder<String>(
      valueListenable: prefs.codeTheme,
      builder: (_, themeId, __) {
        final bg =
            CodeHighlight.themeBackgrounds[themeId] ?? const Color(0xFF282A36);
        final fg =
            CodeHighlight.themeForegrounds[themeId] ?? const Color(0xFFF8F8F2);
        final dim = fg.withOpacity(0.62);
        return Container(
          margin: const EdgeInsets.only(top: 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(P.r12),
            border: Border.all(color: P.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  children: [
                    Text(
                      languageTag.trim().isEmpty
                          ? 'CODE'
                          : languageTag.trim().toUpperCase(),
                      style: PT.monoEyebrow.copyWith(color: dim),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: code));
                        toast(context, 'Code copied');
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.copy_rounded, size: 15, color: dim),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: fg.withOpacity(0.12)),
              FutureBuilder<TextSpan>(
                future: CodeHighlight.instance
                    .highlight(code, languageTag, themeId),
                builder: (_, snap) {
                  final span = snap.data ?? TextSpan(text: code);
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.all(12),
                    child: SelectableText.rich(
                      span,
                      style: const TextStyle(
                        fontFamily: 'JetBrainsMono',
                        fontSize: 12.5,
                        height: 1.5,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
