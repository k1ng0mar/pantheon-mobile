/// Tail of a log from `GET /api/logs`:
/// {"source": "agent", "lines": […], "note"?}.
class LogTail {
  final String source;
  final List<String> lines;
  final String? note;

  LogTail({required this.source, required this.lines, this.note});

  factory LogTail.fromJson(Map<String, dynamic> j) => LogTail(
        source: j['source'] as String? ?? '',
        lines: (j['lines'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
        note: j['note'] as String?,
      );
}
