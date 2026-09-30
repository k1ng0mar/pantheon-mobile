import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'code_block.dart';

/// Chat message text with fenced code blocks parsed out.
///
/// ```` ```dart … ``` ```` segments render as [CodeBlock] (syntax
/// highlighted, theme from Appearance, with its own copy button);
/// everything else renders as selectable text with a custom long-press
/// menu: Copy (selection, or the whole segment), Copy Markdown (the raw
/// source), and Quote in reply (when [onQuote] is supplied). An
/// unterminated fence is treated as plain text so nothing ever
/// disappears.
class MessageContent extends StatelessWidget {
  final String text;
  final TextStyle textStyle;

  /// Called with the full message text when the user picks "Quote in
  /// reply". Null = the menu omits the quote item.
  final ValueChanged<String>? onQuote;

  const MessageContent(
      {super.key,
      required this.text,
      required this.textStyle,
      this.onQuote});

  static final _fence = RegExp(r'```(\w*)\s*\n([\s\S]*?)```');

  @override
  Widget build(BuildContext context) {
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
