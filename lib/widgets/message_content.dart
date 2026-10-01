import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/pantheon_api.dart';
import '../theme.dart';
import 'chat_markdown.dart';
import 'code_block.dart';
import 'forms.dart';
import 'link_preview_card.dart';

/// Chat message text with fenced code blocks parsed out.
///
/// ```` ```dart … ``` ```` segments render as [CodeBlock] (syntax
/// highlighted, theme from Appearance, labeled "CODE"/language, with its
/// own copy button); everything else renders as markdown ([ChatMarkdown]:
/// headings, bold/italic, inline code, lists, real tables) with a custom
/// long-press menu: Copy (selection, or the whole segment), Copy
/// Markdown (the raw source), and Quote in reply (when [onQuote] is
/// supplied). An unterminated fence is treated as plain text so nothing
/// ever disappears.
///
/// When [cards] is true (assistant messages), long text segments render
/// as labeled "Writing" cards with their own copy button, mirroring the
/// labeled Code blocks — long-form content stays copyable at a tap.
class MessageContent extends StatelessWidget {
  final String text;
  final TextStyle textStyle;

  /// Called with the full message text when the user picks "Quote in
  /// reply". Null = the menu omits the quote item.
  final ValueChanged<String>? onQuote;

  /// Dashboard API used for link previews. Null = no preview cards.
  final PantheonApi? api;

  /// Render long text segments as labeled "Writing" copy cards.
  final bool cards;

  const MessageContent(
      {super.key,
      required this.text,
      required this.textStyle,
      this.onQuote,
      this.api,
      this.cards = false});

  static final _fence = RegExp(r'```(\w*)\s*\n([\s\S]*?)```');

  /// First http(s) URL in [text], ignoring fenced code blocks.
  /// Trailing sentence punctuation is trimmed.
  static final _url = RegExp(r'https?://[^\s<>"\u201c\u201d]+');

  /// A text segment this long renders as a "Writing" card (with copy
  /// button) instead of inline prose.
  static const _writingCardMinChars = 600;

  static String? firstUrl(String text) {
    final plain = text.replaceAll(_fence, ' ');
    final m = _url.firstMatch(plain);
    if (m == null) return null;
    var url = m.group(0)!;
    url = url.replaceAll(RegExp(r'[.,;:!?)\]}]+$'), '');
    return url.isEmpty ? null : url;
  }

  @override
  Widget build(BuildContext context) {
    final content = _content();
    final api = this.api;
    if (api == null) return content;
    final previewUrl = firstUrl(text);
    if (previewUrl == null) return content;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        content,
        LinkPreviewCard(url: previewUrl, api: api),
      ],
    );
  }

  Widget _content() {
    final matches = _fence.allMatches(text).toList();
    if (matches.isEmpty) {
      return _textSegment(text);
    }
    final children = <Widget>[];
    var pos = 0;
    for (final m in matches) {
      final before = text.substring(pos, m.start).trim();
      if (before.isNotEmpty) {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: _textSegment(before),
        ));
      }
      children.add(CodeBlock(
        code: m.group(2)!.replaceAll(RegExp(r'\n$'), ''),
        languageTag: m.group(1) ?? '',
      ));
      pos = m.end;
    }
    final after = text.substring(pos).trim();
    if (after.isNotEmpty) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: 6),
        child: _textSegment(after),
      ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  /// One non-code segment: a labeled "Writing" copy card when [cards]
  /// is on and the segment is long-form, plain markdown otherwise.
  /// There is no edit affordance: the backend exposes no message-edit
  /// endpoint, so a copy card is the honest maximum.
  Widget _textSegment(String segment) {
    if (cards && segment.trim().length >= _writingCardMinChars) {
      return _WritingCard(
        source: segment,
        textStyle: textStyle,
        contextMenuBuilder: _menuBuilder,
      );
    }
    return _selectable(segment);
  }

  Widget _selectable(String segment) {
    return ChatMarkdown(
      text: segment,
      textStyle: textStyle,
      contextMenuBuilder: _menuBuilder,
    );
  }

  Widget _menuBuilder(BuildContext context, EditableTextState editableTextState) {
        final value = editableTextState.currentTextEditingValue;
        final selection = value.selection;
        // Selection offsets map to the rendered text, so copy from the
        // live value rather than the raw markdown source.
        final selected = selection.isValid && !selection.isCollapsed
            ? selection.textInside(value.text)
            : value.text;
        return AdaptiveTextSelectionToolbar.buttonItems(
          anchors: editableTextState.contextMenuAnchors,
          buttonItems: [
            ContextMenuButtonItem(
              label: 'Copy',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: selected));
                editableTextState.hideToolbar();
              },
            ),
            ContextMenuButtonItem(
              label: 'Copy Markdown',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: text));
                editableTextState.hideToolbar();
              },
            ),
            if (onQuote != null)
              ContextMenuButtonItem(
                label: 'Quote in reply',
                onPressed: () {
                  editableTextState.hideToolbar();
                  onQuote!(text);
                },
              ),
          ],
        );
  }
}

/// Labeled long-form text card: the "Writing" counterpart to [CodeBlock].
/// Header carries the type label and a copy button (copies the raw
/// markdown source); the body renders full markdown. Used for assistant
/// messages' long text segments so document-style output is copyable
/// at a tap, like ChatGPT/Claude.
class _WritingCard extends StatelessWidget {
  final String source;
  final TextStyle textStyle;
  final Widget Function(BuildContext, EditableTextState)? contextMenuBuilder;

  const _WritingCard({
    required this.source,
    required this.textStyle,
    this.contextMenuBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border.all(color: P.border),
        borderRadius: BorderRadius.circular(P.r8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Text('WRITING',
                    style: PT.monoEyebrow
                        .copyWith(color: P.inkSecondary)),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: source));
                    toast(context, 'Writing copied');
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.copy_rounded,
                        size: 15, color: P.inkSecondary),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: P.border),
          Padding(
            padding: const EdgeInsets.all(12),
            child: ChatMarkdown(
              text: source,
              textStyle: textStyle,
              contextMenuBuilder: contextMenuBuilder,
            ),
          ),
        ],
      ),
    );
  }
}
