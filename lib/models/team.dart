/// An expert team from `GET /api/teams`:
/// {"id","name","description","brief_template","members":
///  [{"name","role","profile","color","icon"}]}.
///
/// Member `color` is a CSS hex string (e.g. "#7c5cff"); the UI parses it.
/// `icon` names the member's icon and may be absent.
class Team {
  final String id;
  final String name;
  final String description;
  final String briefTemplate;
  final List<TeamMember> members;

  Team({
    required this.id,
    required this.name,
    required this.description,
    required this.briefTemplate,
    required this.members,
  });

  factory Team.fromJson(Map<String, dynamic> j) {
    final members = (j['members'] as List?) ?? [];
    return Team(
      id: j['id']?.toString() ?? '',
      name: j['name']?.toString() ?? '',
      description: j['description']?.toString() ?? '',
      briefTemplate: j['brief_template']?.toString() ?? '',
      members: members
          .whereType<Map>()
          .map((e) => TeamMember.fromJson(e.cast<String, dynamic>()))
          .toList(),
    );
  }
}

/// One member of a [Team]'s roster.
class TeamMember {
  final String name;
  final String role;
  final String profile;
  final String color;
  final String? icon;

  TeamMember({
    required this.name,
    required this.role,
    required this.profile,
    required this.color,
    this.icon,
  });

  factory TeamMember.fromJson(Map<String, dynamic> j) => TeamMember(
        name: j['name']?.toString() ?? '',
        role: j['role']?.toString() ?? '',
        profile: j['profile']?.toString() ?? '',
        color: j['color']?.toString() ?? '',
        icon: j['icon'] as String?,
      );
}
