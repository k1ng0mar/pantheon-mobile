/// Run-control constructs the dashboard exposes for the TUI's
/// rewind/checkpoint/goal/background-task commands, now also reachable
/// from the mobile chat slash commands.

/// `POST /api/runs/:id/rewind` → `{"ok": true, "rewound_turn_id",
/// "draft"}`. `draft` is the dropped user message, restored into the
/// composer client-side like the TUI does.
class RewindResult {
  final String rewoundTurnId;
  final String draft;

  const RewindResult({required this.rewoundTurnId, required this.draft});

  factory RewindResult.fromJson(Map<String, dynamic> j) => RewindResult(
        rewoundTurnId: j['rewound_turn_id']?.toString() ?? '',
        draft: j['draft']?.toString() ?? '',
      );
}

/// `POST /api/runs/:id/reset` → `{"ok": true, "canceled"}`. `canceled`
/// is true when a running turn was canceled as part of the reset.
class ResetResult {
  final bool canceled;

  const ResetResult({required this.canceled});

  factory ResetResult.fromJson(Map<String, dynamic> j) =>
      ResetResult(canceled: j['canceled'] == true);
}

/// One entry of `GET /api/runs/:id/checkpoints` →
/// `{"checkpoints": [{"name", "turn_no", "restorable"}]}`. The create
/// endpoint answers `{"ok": true, "name", "turn_no"}` (no `restorable`
/// key), so it defaults to true.
class Checkpoint {
  final String name;
  final int turnNo;
  final bool restorable;

  const Checkpoint(
      {required this.name, required this.turnNo, this.restorable = true});

  factory Checkpoint.fromJson(Map<String, dynamic> j) {
    final n = j['turn_no'];
    return Checkpoint(
      name: j['name']?.toString() ?? '',
      turnNo: n is num ? n.toInt() : int.tryParse(n.toString()) ?? 0,
      restorable: j['restorable'] == null ? true : j['restorable'] == true,
    );
  }
}

/// `POST /api/runs/:id/restore` → `{"ok": true, "name",
/// "rewound_to_turn"}`.
class RestoreResult {
  final String name;
  final int rewoundToTurn;

  const RestoreResult({required this.name, required this.rewoundToTurn});

  factory RestoreResult.fromJson(Map<String, dynamic> j) {
    final n = j['rewound_to_turn'];
    return RestoreResult(
      name: j['name']?.toString() ?? '',
      rewoundToTurn: n is num ? n.toInt() : int.tryParse(n.toString()) ?? 0,
    );
  }
}

/// `GET /api/runs/:id/goal` → `{"goal": null | {"text",
/// "iterations_used", "max_iterations"}}`.
class RunGoal {
  final String text;
  final int iterationsUsed;
  final int? maxIterations;

  const RunGoal(
      {required this.text, required this.iterationsUsed, this.maxIterations});

  factory RunGoal.fromJson(Map<String, dynamic> j) {
    int? asInt(Object? v) =>
        v is num ? v.toInt() : int.tryParse(v.toString());
    return RunGoal(
      text: j['text']?.toString() ?? '',
      iterationsUsed: asInt(j['iterations_used']) ?? 0,
      maxIterations: asInt(j['max_iterations']),
    );
  }
}

/// A by-the-way background task: list/detail shapes merged. `output`
/// is null while the task is still running.
class BackgroundTask {
  final String id;
  final String status;
  final String label;
  final String? runId;
  final int? elapsedS;
  final String? output;

  const BackgroundTask(
      {required this.id,
      required this.status,
      required this.label,
      this.runId,
      this.elapsedS,
      this.output});

  factory BackgroundTask.fromJson(Map<String, dynamic> j) {
    final e = j['elapsed_s'];
    return BackgroundTask(
      id: j['id']?.toString() ?? '',
      status: j['status']?.toString() ?? '',
      label: j['label']?.toString() ?? '',
      runId: j['run_id']?.toString(),
      elapsedS: e is num ? e.toInt() : int.tryParse(e.toString()),
      output: j['output']?.toString(),
    );
  }
}
