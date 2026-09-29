/// A schedule template from `GET /api/schedule/templates`:
/// {"name","description","schedule":{"type","expr"|"duration"},"vars":[…]}.
class TemplateVar {
  final String name;
  final String? question;
  final String? defaultValue;
  final bool reserved;

  TemplateVar(
      {required this.name,
      this.question,
      this.defaultValue,
      required this.reserved});

  factory TemplateVar.fromJson(Map<String, dynamic> j) => TemplateVar(
        name: j['name'] as String? ?? '',
        question: j['question'] as String?,
        defaultValue: j['default']?.toString(),
        reserved: j['reserved'] as bool? ?? false,
      );
}

class ScheduleTemplate {
  final String name;
  final String? description;
  final String scheduleType; // "every" | "cron"
  final String scheduleDetail; // duration string or cron expr
  final List<TemplateVar> vars;

  ScheduleTemplate({
    required this.name,
    this.description,
    required this.scheduleType,
    required this.scheduleDetail,
    required this.vars,
  });

  factory ScheduleTemplate.fromJson(Map<String, dynamic> j) {
    final s = j['schedule'] is Map
        ? (j['schedule'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};
    final vars = (j['vars'] as List?) ?? [];
    return ScheduleTemplate(
      name: j['name'] as String? ?? '',
      description: j['description'] as String?,
      scheduleType: s['type'] as String? ?? 'every',
      scheduleDetail:
          (s['expr'] ?? s['duration'])?.toString() ?? '',
      vars: vars
          .whereType<Map>()
          .map((e) => TemplateVar.fromJson(e.cast<String, dynamic>()))
          .toList(),
    );
  }
}
