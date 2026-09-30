/// Schedule kind as returned by `GET /api/schedule/jobs`.
/// `kind` is a tagged object, e.g. `{"type":"cron","expr":"0 9 * * *"}`,
/// `{"type":"every","every_ms":3600000}`, `{"type":"manual"}`.
class JobKind {
  final String type;
  final String? expr;
  final int? everyMs;
  final int? atMs;
  final String? path;

  const JobKind({
    required this.type,
    this.expr,
    this.everyMs,
    this.atMs,
    this.path,
  });

  factory JobKind.fromJson(dynamic j) {
    if (j is Map) {
      final m = j.cast<String, dynamic>();
      return JobKind(
        type: m['type'] as String? ?? 'unknown',
        expr: m['expr'] as String?,
        everyMs: (m['every_ms'] as num?)?.toInt(),
        atMs: (m['at_ms'] as num?)?.toInt(),
        path: m['path'] as String?,
      );
    }
    // Be lenient if the API ever sends a plain string.
    return JobKind(type: j?.toString() ?? 'unknown');
  }

  /// Short human-readable description of the trigger.
  String get display {
    switch (type) {
      case 'cron':
        // Cron has no timezone support: it fires in the dashboard
        // server's local time. Say so wherever the schedule is shown.
        return '${expr ?? 'cron'} · server time';
      case 'every':
        return everyMs != null ? _fmtDuration(everyMs!) : 'every';
      case 'oneshot':
        return atMs != null ? 'once ${_fmtDate(atMs!)}' : 'once';
      case 'webhook':
        return path ?? 'webhook';
      case 'conditional':
        return expr ?? 'conditional';
      case 'manual':
        return 'manual';
      default:
        return type;
    }
  }

  static String _fmtDuration(int ms) {
    final s = ms ~/ 1000;
    if (s < 60) return 'every ${s}s';
    final m = s ~/ 60;
    if (m < 60) return 'every ${m}m';
    final h = m ~/ 60;
    if (h < 24) return 'every ${h}h';
    return 'every ${h ~/ 24}d';
  }

  static String _fmtDate(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    return '${d.year}-${_two(d.month)}-${_two(d.day)}';
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
}

class ScheduledJob {
  final String id;
  final String task;
  final JobKind kind;
  final String? agent;
  final bool paused;
  final int? lastRunMs;
  final int? nextFireMs;
  final String? model;
  final String? provider;

  ScheduledJob({
    required this.id,
    required this.task,
    required this.kind,
    this.agent,
    required this.paused,
    this.lastRunMs,
    this.nextFireMs,
    this.model,
    this.provider,
  });

  factory ScheduledJob.fromJson(Map<String, dynamic> j) => ScheduledJob(
        id: j['id'] as String? ?? '',
        task: j['task'] as String? ?? '',
        kind: JobKind.fromJson(j['kind']),
        agent: j['agent'] as String?,
        paused: j['paused'] as bool? ?? false,
        lastRunMs: ((j['last_run_ms'] ?? j['last_run']) as num?)?.toInt(),
        nextFireMs: (j['next_fire_ms'] as num?)?.toInt(),
        model: j['model'] as String?,
        provider: j['provider'] as String?,
      );
}
