/// Open Graph / page metadata for a URL, from
/// `GET /api/link-preview?url=`. Every field is nullable — the backend
/// only fills what the page actually exposes.
class LinkPreview {
  final String? title;
  final String? description;
  final String? image;
  final String? siteName;

  const LinkPreview({
    this.title,
    this.description,
    this.image,
    this.siteName,
  });

  factory LinkPreview.fromJson(Map<String, dynamic> j) {
    String? s(String key) {
      final v = j[key];
      if (v is! String) return null;
      final t = v.trim();
      return t.isEmpty ? null : t;
    }

    return LinkPreview(
      title: s('title'),
      description: s('description'),
      image: s('image'),
      siteName: s('site_name'),
    );
  }

  /// A preview with nothing to show (no title, description, or image)
  /// is not worth rendering a card for.
  bool get usable =>
      title != null || description != null || image != null;
}
