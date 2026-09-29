import 'package:flutter/material.dart';

import 'code_block.dart';

/// Chat message text with fenced code blocks parsed out.
///
/// ```` ```dart … ``` ```` segments render as [CodeBlock] (syntax
/// highlighted, theme from Appearance); everything else renders as the
/// usual selectable text. An unterminated fence is treated as plain text
/// so nothing ever disappears.
class MessageContent extends StatelessWidget {
  final String text;
  final TextStyle textStyle;

  const MessageContent(
      {super.key, required this.text, required this.textStyle});

  static final _fence = RegExp(r'```(\w*)\s*\n([\s\S]*?)```');

  @override
  Widget build(BuildContext context) {
    final matches = _fence.allMatches(text).toList();
    if (matches.isEmpty) {
      return SelectableText(text, style: textStyle);
    }
    final children = <Widget>[];
    var pos = 0;
    for (final m in matches) {
      final before = text.substring(pos, m.start).trim();
      if (before.isNotEmpty) {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: SelectableText(before, style: textStyle),
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
        child: SelectableText(after, style: textStyle),
      ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}
