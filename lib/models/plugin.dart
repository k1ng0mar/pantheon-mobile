/// A plugin/extension from `GET /api/plugins`:
/// {"kind","name","version","description","enabled","bundled",
///  "approved","location"}.
class Plugin {
  final String kind; // "tool" | "hook"
  final String name;
  final String? version;
  final String? description;
  final bool enabled;
  final bool bundled;
  final bool approved;
  final String? location;

  Plugin({
    required this.kind,
    required this.name,
    this.version,
    this.description,
    required this.enabled,
    required this.bundled,
    required this.approved,
    this.location,
  });

  factory Plugin.fromJson(Map<String, dynamic> j) => Plugin(
        kind: j['kind'] as String? ?? 'tool',
        name: j['name'] as String? ?? '',
        version: j['version'] as String?,
        description: j['description'] as String?,
        enabled: j['enabled'] as bool? ?? true,
        bundled: j['bundled'] as bool? ?? false,
        approved: j['approved'] as bool? ?? false,
        location: j['location'] as String?,
      );
}
