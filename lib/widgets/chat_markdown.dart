import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';

/// Compact markdown renderer for chat messages: headings, bold/italic,
/// inline code, lists, and real tables — not monospace dumps.
///
/// Fenced code blocks never reach this widget: [MessageContent] splits
/// them out first and renders them as [CodeBlock] (which owns its copy
/// button). Every other segment renders here.
///
/// Selection menus are supplied per text block via [contextMenuBuilder]
/// so the chat's Copy / Copy Markdown / Quote in reply menu survives.
class ChatMarkdown extends StatelessWidget {
  final String text;
  final TextStyle textStyle;

  /// (context, editableState) → toolbar, mirroring SelectableText's
  /// contextMenuBuilder signature.
  final Widget Function(BuildContext, EditableTextState)? contextMenuBuilder;

  const ChatMarkdown({
    super.key,
    required this.text,
    required this.textStyle,
    this.contextMenuBuilder,
  });

  TextStyle get _mono => PT.monoSm.copyWith(
        color: P.ink,
        backgroundColor: P.tonal,
      );

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  /// Inline spans: **bold**, *italic*, `code`, [label](url).
  List<InlineSpan> _inline(String src) {
    final spans = <InlineSpan>[];
    final re = RegExp(
        r'\*\*(.+?)\*\*|__([^_]+?)__|`([^`]+?)`|\[([^\]]+?)\]\(([^)]+?)\)|\*([^*\n]+?)\*');
    var pos = 0;
    for (final m in re.allMatches(src)) {
      if (m.start > pos) {
        spans.add(TextSpan(text: src.substring(pos, m.start)));
      }
      if (m.group(1) != null || m.group(2) != null) {
        spans.add(TextSpan(
          text: m.group(1) ?? m.group(2),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ));
      } else if (m.group(3) != null) {
        spans.add(TextSpan(text: m.group(3), style: _mono));
      } else if (m.group(4) != null) {
        final url = m.group(5)!;
        spans.add(TextSpan(
          text: m.group(4),
          style: TextStyle(
              color: P.accent, decoration: TextDecoration.underline),
          recognizer: TapGestureRecognizer()..onTap = () => _openUrl(url),
        ));
      } else {
        spans.add(TextSpan(
          text: m.group(6),
          style: const TextStyle(fontStyle: FontStyle.italic),
        ));
      }
      pos = m.end;
    }
    if (pos < src.length) {
      spans.add(TextSpan(text: src.substring(pos)));
    }
    return spans;
  }

  static final _headingRe = RegExp(r'^(#{1,3})\s+(.*)$');
  static final _listRe = RegExp(r'^(\s*)([-*+]|\d+[.)])\s+(.*)$');
  static final _tableSepRe =
      RegExp(r'^\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$');

  static bool _isTableRow(String line) =>
      line.trim().startsWith('|') && line.trim().endsWith('|');

  static List<String> _splitRow(String line) {
    var t = line.trim();
    if (t.startsWith('|')) t = t.substring(1);
    if (t.endsWith('|')) t = t.substring(0, t.length - 1);
    return t.split('|').map((c) => c.trim()).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: _blocks(),
    );
  }

  List<Widget> _blocks() {
    final lines = text.split('\n');
    final out = <Widget>[];
    final para = <String>[];

    void flushPara() {
      if (para.isEmpty) return;
      final t = para.join('\n').trim();
      para.clear();
      if (t.isEmpty) return;
      out.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: SelectableText.rich(
          TextSpan(children: _inline(t), style: textStyle),
          contextMenuBuilder: contextMenuBuilder,
        ),
      ));
    }

    var i = 0;
    while (i < lines.length) {
      final line = lines[i];
      final h = _headingRe.firstMatch(line);
      if (h != null) {
        flushPara();
        out.add(_heading(h.group(1)!.length, h.group(2)!));
        i++;
        continue;
      }
      if (line.trim().isEmpty) {
        flushPara();
        i++;
        continue;
      }
      if (_isTableRow(line) &&
          i + 1 < lines.length &&
          _tableSepRe.hasMatch(lines[i + 1])) {
        flushPara();
        final header = _splitRow(line);
        i += 2;
        final body = <List<String>>[];
        while (i < lines.length && _isTableRow(lines[i])) {
          body.add(_splitRow(lines[i]));
          i++;
        }
        out.add(_table(header, body));
        continue;
      }
      if (_listRe.hasMatch(line)) {
        flushPara();
        final items = <_ListItem>[];
        while (i < lines.length) {
          final m = _listRe.firstMatch(lines[i]);
          if (m == null) break;
          items.add(_ListItem(
            ordered: RegExp(r'^\d').hasMatch(m.group(2)!),
            text: m.group(3)!,
          ));
          i++;
        }
        out.add(_list(items));
        continue;
      }
      para.add(line);
      i++;
    }
    flushPara();
    return out;
  }

  Widget _heading(int level, String raw) {
    final size = level == 1 ? 20.0 : level == 2 ? 17.0 : 15.0;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 6),
      child: SelectableText.rich(
        TextSpan(
          children: _inline(raw.trim()),
          style: textStyle.copyWith(
              fontSize: size, fontWeight: FontWeight.w700),
        ),
        contextMenuBuilder: contextMenuBuilder,
      ),
    );
  }

  Widget _list(List<_ListItem> items) {
    var num = 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final it in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 22,
                    child: Text(
                      it.ordered ? '${++num}.' : '•',
                      style: textStyle.copyWith(color: P.inkSecondary),
                    ),
                  ),
                  Expanded(
                    child: SelectableText.rich(
                      TextSpan(
                          children: _inline(it.text), style: textStyle),
                      contextMenuBuilder: contextMenuBuilder,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _table(List<String> header, List<List<String>> body) {
    final width = header.length;
    List<String> pad(List<String> cells) {
      final c = List<String>.from(cells);
      while (c.length < width) {
        c.add('');
      }
      return c.take(width).toList();
    }

    TableRow row(List<String> cells, {required bool head}) {
      final style = head
          ? textStyle.copyWith(fontWeight: FontWeight.w700)
          : textStyle;
      return TableRow(
        decoration:
            head ? BoxDecoration(color: P.tonal) : null,
        children: [
          for (final c in pad(cells))
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 8),
              child: Text.rich(
                TextSpan(children: _inline(c), style: style),
              ),
            ),
        ],
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border.all(color: P.border),
        borderRadius: BorderRadius.circular(P.r8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(P.r8),
        child: Table(
          border: TableBorder(
            horizontalInside: BorderSide(color: P.border, width: 1),
            verticalInside: BorderSide(color: P.border, width: 1),
          ),
          children: [
            row(header, head: true),
            for (final b in body) row(b, head: false),
          ],
        ),
      ),
    );
  }
}

class _ListItem {
  final bool ordered;
  final String text;
  _ListItem({required this.ordered, required this.text});
}
