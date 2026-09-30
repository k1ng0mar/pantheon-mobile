/// A stored chat attachment from `POST /api/uploads`:
///
/// ```json
/// {"id": "upl_…", "name": "photo.jpg", "mime": "image/jpeg",
///  "size_bytes": 48210}
/// ```
///
/// The id is passed back to `POST /api/runs/:id/message` as an
/// attachment; the backend appends the file's path to the turn input so
/// the agent can read it.
class UploadRecord {
  final String id;
  final String name;
  final String mime;
  final int sizeBytes;

  UploadRecord({
    required this.id,
    required this.name,
    required this.mime,
    required this.sizeBytes,
  });

  factory UploadRecord.fromJson(Map<String, dynamic> j) => UploadRecord(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        mime: j['mime'] as String? ?? 'application/octet-stream',
        sizeBytes: (j['size_bytes'] as num?)?.toInt() ?? 0,
      );

  /// "48.2 KB" / "3.1 MB" for chip labels.
  String get sizeLabel {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  bool get isImage => mime.startsWith('image/');
}
