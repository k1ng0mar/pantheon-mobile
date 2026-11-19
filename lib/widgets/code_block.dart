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
class CodeBlock extends StatefulWidget {
  final String code;
  final String languageTag;

  const CodeBlock({super.key, required this.code, required this.languageTag});

  @override
  State<CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<CodeBlock> {
  // The highlight future is memoized per (code, language, theme) so an
  // unrelated parent rebuild doesn't re-run syntax highlighting.
  late Future<TextSpan> _highlighted;
  late String _code;
  late String _languageTag;
  late String _themeId;

  /// Shared by the horizontal code scroller and its visible scrollbar,
  /// so wide code shows a scroll cue instead of silently clipping.
  final ScrollController _codeScroll = ScrollController();

  /// Long code is previewed at this many lines; a counted footer expands
  /// it. A 500-line block must not become a 500-line-tall card.
  static const int _previewMaxLines = 16;
  static const double _previewMaxHeight = 324;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _code = widget.code;
    _languageTag = widget.languageTag;
    _themeId = AppPreferences.instance.codeTheme.value;
    _highlight();
  }

  @override
  void dispose() {
    _codeScroll.dispose();
    super.dispose();
  }

  void _highlight() {
    _highlighted = CodeHighlight.instance
        .highlight(_code, _languageTag, _themeId);
  }

  /// The highlighted code in a horizontal scroller. Long code is bounded
  /// to a preview height until expanded; horizontal scroll and its
  /// scrollbar cue are kept in both states so wide lines never silently
  /// clip.
  Widget _codeArea() {
    final view = FutureBuilder<TextSpan>(
      future: _highlighted,
      builder: (_, snap) {
        final span = snap.data ?? TextSpan(text: widget.code);
        return Scrollbar(
          controller: _codeScroll,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _codeScroll,
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
          ),
        );
      },
    );
    final lines = widget.code.split('\n').length;
    if (lines <= _previewMaxLines || _expanded) return view;
    return ClipRect(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: _previewMaxHeight),
        child: view,
      ),
    );
  }

  /// Counted expand/collapse affordance: the remainder is always named,
  /// never silently cut.
  Widget _expandFooter(int lines, Color dim) {
    return InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(
              _expanded
                  ? Icons.unfold_less_rounded
                  : Icons.unfold_more_rounded,
              size: 15,
              color: dim,
            ),
            const SizedBox(width: 6),
            Text(
              _expanded ? 'Collapse' : 'Show all $lines lines',
              style: PT.monoEyebrow.copyWith(color: dim),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prefs = AppPreferences.instance;
    return ValueListenableBuilder<String>(
      valueListenable: prefs.codeTheme,
      builder: (_, themeId, __) {
        // Re-highlight only when the inputs actually changed. Assigning
        // the cached fields here (without setState) is safe: the rebuild
        // already reflects the new inputs, and the FutureBuilder below
        // shows the previous result until the new future completes.
        if (themeId != _themeId ||
            widget.code != _code ||
            widget.languageTag != _languageTag) {
          _themeId = themeId;
          _code = widget.code;
          _languageTag = widget.languageTag;
          _highlight();
        }
        final bg =
            CodeHighlight.themeBackgrounds[themeId] ?? const Color(0xFF282A36);
        final fg =
            CodeHighlight.themeForegrounds[themeId] ?? const Color(0xFFF8F8F2);
        final dim = fg.withValues(alpha: 0.62);
        final lines = widget.code.split('\n').length;
        final long = lines > _previewMaxLines;
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
                      widget.languageTag.trim().isEmpty
                          ? 'CODE'
                          : widget.languageTag.trim().toUpperCase(),
                      style: PT.monoEyebrow.copyWith(color: dim),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(
                            ClipboardData(text: widget.code));
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
              Divider(height: 1, color: fg.withValues(alpha: 0.12)),
              _codeArea(),
              if (long) _expandFooter(lines, dim),
            ],
          ),
        );
      },
    );
  }
}
