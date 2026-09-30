import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/pantheon_api.dart';
import 'code_block.dart';
import 'link_preview_card.dart';

/// Chat message text with fenced code blocks parsed out.
///
/// ```` ```dart … ``` ```` segments render as [CodeBlock] (syntax
/// highlighted, theme from Appearance, with its own copy button);
/// everything else renders as selectable text with a custom long-press
/// menu: Copy (selection, or the whole segment), Copy Markdown (the raw
/// source), and Quote in reply (when [onQuote] is supplied). An
/// unterminated fence is treated as plain text so nothing ever
/// disappears.
///
/// When [api] is supplied, the first URL in the message (outside code
/// blocks) gets a rich [LinkPreviewCard] rendered under the text.
class MessageContent extends StatelessWidget {
  final String text;
  final TextStyle textStyle;

  /// Called with the full message text when the user picks "Quote in
  /// reply". Null = the menu omits the quote item.
  final ValueChanged<String>? onQuote;

  /// Dashboard API used for link previews. Null = no preview cards.
  final PantheonApi? api;

  const MessageContent(
      {super.key,
      required this.text,
      required this.textStyle,
      this.onQuote,
      this.api});

  static final _fence = RegExp(r'```(\w*)\s*\n([\s\S]*?)```');

  /// First http(s) URL in [text], ignoring fenced code blocks.
  /// Trailing sentence punctuation is trimmed.
  static final _url = RegExp(r'https?://[^\s<>"\u201c\u201d]+');

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
      return _selectable(text);
    }
    final children = <Widget>[];
    var pos = 0;
    for (final m in matches) {
      final before = text.substring(pos, m.start).trim();
      if (before.isNotEmpty) {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: _selectable(before),
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
        child: _selectable(after),
      ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  Widget _selectable(String segment) {
    return SelectableText(
      segment,
      style: textStyle,
      contextMenuBuilder: (context, editableTextState) {
        final selection =
            editableTextState.currentTextEditingValue.selection;
        final selected = selection.isValid && !selection.isCollapsed
            ? selection.textInside(segment)
            : segment;
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
      },
    );
  }
}
