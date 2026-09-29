import 'package:flutter/material.dart';
import 'package:syntax_highlight/syntax_highlight.dart';

/// Syntax highlighting for chat code blocks, powered by the
/// `syntax_highlight` package (TextMate grammars, VS Code-style themes).
///
/// The package's bundled themes didn't include the three Umar picked, so
/// the theme JSONs live in this app's assets (`assets/themes/`) and are
/// loaded through the package's own theme loader — same engine, our
/// themes.
class CodeHighlight {
  CodeHighlight._();
  static final CodeHighlight instance = CodeHighlight._();

  /// Grammar ids the package ships (see its docs). Anything else renders
  /// as plain mono text.
  static const supportedLanguages = <String>{
    'css',
    'dart',
    'go',
    'html',
    'java',
    'javascript',
    'json',
    'kotlin',
    'python',
    'rust',
    'sql',
    'swift',
    'typescript',
    'yaml',
  };

  /// Common fence-tag aliases mapped onto supported grammars.
  static const _aliases = <String, String>{
    'py': 'python',
    'js': 'javascript',
    'jsx': 'javascript',
    'ts': 'typescript',
    'tsx': 'typescript',
    'rs': 'rust',
    'kt': 'kotlin',
    'kts': 'kotlin',
    'yml': 'yaml',
    'xml': 'html',
  };

  static const themeIds = <String>['github', 'dracula', 'atom-one-dark'];

  static const themeLabels = <String, String>{
    'github': 'GitHub',
    'dracula': 'Dracula',
    'atom-one-dark': 'Atom One Dark',
  };

  /// Code block surface per theme — each theme carries its own background
  /// so the block looks right in either app brightness.
  static const themeBackgrounds = <String, Color>{
    'github': Color(0xFFFFFFFF),
    'dracula': Color(0xFF282A36),
    'atom-one-dark': Color(0xFF282C34),
  };

  static const themeForegrounds = <String, Color>{
    'github': Color(0xFF1F2328),
    'dracula': Color(0xFFF8F8F2),
    'atom-one-dark': Color(0xFFABB2BF),
  };

  Future<void>? _initFuture;
  final _themeCache = <String, HighlighterTheme>{};

  Future<void> _ensureInit() =>
      _initFuture ??= Highlighter.initialize(supportedLanguages.toList());

  /// Normalize a fence tag (` ```dart `) to a supported grammar id, or
  /// null when the language has no grammar (renders plain).
  static String? canonicalLanguage(String tag) {
    final t = tag.trim().toLowerCase();
    if (t.isEmpty) return null;
    if (supportedLanguages.contains(t)) return t;
    return _aliases[t];
  }

  Future<HighlighterTheme> _theme(String themeId) async {
    final id = themeIds.contains(themeId) ? themeId : 'dracula';
    final cached = _themeCache[id];
    if (cached != null) return cached;
    final loaded = await HighlighterTheme.loadFromAssets(
      ['assets/themes/$id.json'],
      TextStyle(
        fontFamily: 'JetBrainsMono',
        fontSize: 12.5,
        height: 1.5,
        color: themeForegrounds[id],
      ),
    );
    _themeCache[id] = loaded;
    return loaded;
  }

  /// Highlight [code], returning a [TextSpan] ready for `Text.rich` /
  /// `SelectableText.rich`. Unknown languages return an unstyled span
  /// (the widget applies the mono fallback style).
  Future<TextSpan> highlight(
      String code, String languageTag, String themeId) async {
    await _ensureInit();
    final language = canonicalLanguage(languageTag);
    if (language == null) return TextSpan(text: code);
    final theme = await _theme(themeId);
    return Highlighter(language: language, theme: theme).highlight(code);
  }
}
