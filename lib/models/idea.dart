/// An idea proposed by the nightly pass, from `GET /api/ideas`:
///
/// ```json
/// {"ideas":[{
///   "id": "…",
///   "title": "…",
///   "description": "…",
///   "includes": ["step one", "step two"],
///   "kind": "general" | "scheduled_task",
///   "status": "pending",
///   "created_day": "2026-09-30",
///   "schedule": {…}          // scheduled_task only
/// }]}
/// ```
enum IdeaKind { general, scheduledTask }

class Idea {
  final String id;
  final String title;
  final String description;

  /// The plan steps shown under "What's included".
  final List<String> includes;
  final IdeaKind kind;

  /// `pending` | `accepted` | `dismissed`. Mutable: the app updates it
  /// locally after accept/dismiss so the list re-renders without a
  /// refetch.
  String status;
  final String? createdDay;

  /// Trigger spec for `scheduled_task` ideas (e.g. a cron expr); null
  /// for `general` ideas.
  final Map<String, dynamic>? schedule;

  Idea({
    required this.id,
    required this.title,
    required this.description,
    this.includes = const [],
    this.kind = IdeaKind.general,
    this.status = 'pending',
    this.createdDay,
    this.schedule,
  });

  factory Idea.fromJson(Map<String, dynamic> j) {
    final sched = j['schedule'];
    return Idea(
      id: j['id'] as String? ?? '',
      title: j['title'] as String? ?? '',
      description: j['description'] as String? ?? '',
      includes:
          (j['includes'] as List?)?.whereType<String>().toList() ?? const [],
      kind: j['kind'] == 'scheduled_task'
          ? IdeaKind.scheduledTask
          : IdeaKind.general,
      status: j['status'] as String? ?? 'pending',
      createdDay: j['created_day'] as String?,
      schedule:
          sched is Map ? sched.cast<String, dynamic>() : null,
    );
  }

  bool get isPending => status == 'pending';
  bool get isScheduledTask => kind == IdeaKind.scheduledTask;

  String get kindLabel =>
      isScheduledTask ? 'Scheduled task' : 'Idea';
}
