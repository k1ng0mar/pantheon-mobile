/// A skill from `GET /api/skills`:
/// {"name","description","origin","path","enabled","scope"}.
class Skill {
  final String name;
  final String? description;
  final String? origin;
  final String? path;
  final bool enabled;
  final String scope; // "pantheon" | "external"

  Skill({
    required this.name,
    this.description,
    this.origin,
    this.path,
    required this.enabled,
    required this.scope,
  });

  factory Skill.fromJson(Map<String, dynamic> j) => Skill(
        name: j['name'] as String? ?? '',
        description: j['description'] as String?,
        origin: j['origin'] as String?,
        path: j['path'] as String?,
        enabled: j['enabled'] as bool? ?? true,
        scope: j['scope'] as String? ?? 'external',
      );
}
