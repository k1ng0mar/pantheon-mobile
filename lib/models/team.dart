/// An expert team from `GET /api/teams` / `GET /api/teams/:id`
/// (both use the enriched client shape).
///
/// Members arrive as
/// `{"expert_id","role","profile","expert":{"id","name","color","icon"}}`;
/// `expert` is null when the linked expert was deleted (rendered as
/// unresolved). `lead` carries the lead expert's display identity.
/// `stages` keeps expert ids, joined against `members` by clients.
class Team {
  final String id;
  final String name;
  final String description;
  final String briefTemplate;
  final List<TeamMember> members;

  /// "pipeline" | "parallel_merge" | "review_loop".
  final String topology;

  final String leadExpertId;
  final TeamLead? lead;
  final List<TeamStage> stages;

  Team({
    required this.id,
    required this.name,
    required this.description,
    required this.briefTemplate,
    required this.members,
    this.topology = '',
    this.leadExpertId = '',
    this.lead,
    List<TeamStage>? stages,
  }) : stages = stages ?? const [];

  factory Team.fromJson(Map<String, dynamic> j) {
    final members = (j['members'] as List?) ?? [];
    final stages = (j['stages'] as List?) ?? [];
    final lead = j['lead'];
    return Team(
      id: j['id']?.toString() ?? '',
      name: j['name']?.toString() ?? '',
      description: j['description']?.toString() ?? '',
      briefTemplate: j['brief_template']?.toString() ?? '',
      members: members
          .whereType<Map>()
          .map((e) => TeamMember.fromJson(e.cast<String, dynamic>()))
          .toList(),
      topology: j['topology']?.toString() ?? '',
      leadExpertId: j['lead_expert_id']?.toString() ?? '',
      lead: lead is Map
          ? TeamLead.fromJson(lead.cast<String, dynamic>())
          : null,
      stages: stages
          .whereType<Map>()
          .map((e) => TeamStage.fromJson(e.cast<String, dynamic>()))
          .toList(),
    );
  }

  /// Topology as a human label ("Parallel merge").
  String get topologyLabel {
    final s = topology.replaceAll('_', ' ');
    return s.isEmpty ? '' : s[0].toUpperCase() + s.substring(1);
  }

  TeamMember? memberByExpertId(String expertId) {
    for (final m in members) {
      if (m.expertId == expertId) return m;
    }
    return null;
  }
}

/// One member of a [Team]'s roster.
class TeamMember {
  final String expertId;
  final String name;
  final String role;
  final String profile;
  final String color;
  final String? icon;

  /// True when the linked expert no longer exists.
  final bool unresolved;

  TeamMember({
    required this.expertId,
    required this.name,
    required this.role,
    required this.profile,
    required this.color,
    this.icon,
    this.unresolved = false,
  });

  factory TeamMember.fromJson(Map<String, dynamic> j) {
    final expert = j['expert'];
    final expertMap = expert is Map ? expert.cast<String, dynamic>() : null;
    final expertId = j['expert_id']?.toString() ?? '';
    return TeamMember(
      expertId: expertId,
      name: expertMap?['name']?.toString() ??
          j['name']?.toString() ??
          (expertId.isEmpty ? 'member' : expertId),
      role: j['role']?.toString() ?? '',
      profile: j['profile']?.toString() ?? '',
      color: expertMap?['color']?.toString() ?? j['color']?.toString() ?? '',
      icon: expertMap?['icon'] as String? ?? j['icon'] as String?,
      unresolved: expertMap == null,
    );
  }
}

/// The lead expert's display identity.
class TeamLead {
  final String id;
  final String name;
  final String color;
  final String? icon;

  TeamLead({
    required this.id,
    required this.name,
    required this.color,
    this.icon,
  });

  factory TeamLead.fromJson(Map<String, dynamic> j) => TeamLead(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        color: j['color']?.toString() ?? '',
        icon: j['icon'] as String?,
      );
}

/// One execution stage: ordered member expert ids plus handoff contracts.
class TeamStage {
  final String name;
  final List<String> members;
  final String inputContract;
  final String outputContract;

  /// Name of the stage a review failure loops back to (null when none).
  final String? loopBackTo;

  TeamStage({
    required this.name,
    required this.members,
    required this.inputContract,
    required this.outputContract,
    this.loopBackTo,
  });

  factory TeamStage.fromJson(Map<String, dynamic> j) {
    final members = (j['members'] as List?) ?? [];
    return TeamStage(
      name: j['name']?.toString() ?? '',
      members: members.map((e) => e.toString()).toList(),
      inputContract: j['input_contract']?.toString() ?? '',
      outputContract: j['output_contract']?.toString() ?? '',
      loopBackTo: j['loop_back_to']?.toString(),
    );
  }
}
