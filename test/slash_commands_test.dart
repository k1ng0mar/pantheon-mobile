import 'package:flutter_test/flutter_test.dart';

import 'package:pantheon_mobile/models/approval.dart';
import 'package:pantheon_mobile/models/models.dart';
import 'package:pantheon_mobile/services/pantheon_api.dart';
import 'package:pantheon_mobile/services/slash_commands.dart';

// NOTE: these tests were written in an environment without the
// Flutter/Dart SDK and were never executed here. Run them on Umar's
// machine or CI (`flutter test`) before treating them as green.

class _FakeApi extends PantheonApi {
  _FakeApi() : super(baseUrl: 'http://localhost:1', token: 't');

  List<Approval> pending = [];
  final List<(String, bool)> decided = [];
  String? memoryText;
  String? memoryKind;
  String? swarmTask;
  String? swarmMode;
  int? swarmCount;
  bool? swarmJudge;

  @override
  Future<List<Approval>> approvals() async => pending;

  @override
  Future<void> decideApproval(String id, bool grant,
      {String? mode}) async {
    decided.add((id, grant));
  }

  @override
  Future<MemoryEntry> addMemory({required String text, String? kind}) async {
    memoryText = text;
    memoryKind = kind;
    return MemoryEntry(key: 'k', value: text);
  }

  @override
  Future<Map<String, dynamic>> createSwarm({
    required String task,
    required String mode,
    int? subagentCount,
    List<String>? profiles,
    required bool judge,
  }) async {
    swarmTask = task;
    swarmMode = mode;
    swarmCount = subagentCount;
    swarmJudge = judge;
    return {'swarm_id': 's1'};
  }

  @override
  Future<UsageStats> stats({int days = 30}) async => UsageStats(
        totals: UsageTotals(
            calls: 3,
            inputTokens: 10,
            outputTokens: 5,
            totalTokens: 15,
            costUsd: 0.02),
        byModel: const {},
        byDay: const {},
      );

  // --- run controls ---

  RewindResult? rewindResult;
  Object? rewindError;

  @override
  Future<RewindResult> rewindRun(String id) async {
    if (rewindError != null) throw rewindError!;
    return rewindResult!;
  }

  bool resetCanceled = false;
  Object? resetError;

  @override
  Future<ResetResult> resetRun(String id) async {
    if (resetError != null) throw resetError!;
    return ResetResult(canceled: resetCanceled);
  }

  List<Checkpoint> checkpointList = [];
  Checkpoint? createdCheckpoint;
  String? lastCheckpointName;
  Object? checkpointError;

  @override
  Future<List<Checkpoint>> runCheckpoints(String id) async {
    if (checkpointError != null) throw checkpointError!;
    return checkpointList;
  }

  @override
  Future<Checkpoint> createCheckpoint(String id, {String? name}) async {
    if (checkpointError != null) throw checkpointError!;
    lastCheckpointName = name;
    return createdCheckpoint ??
        Checkpoint(name: name ?? 'auto-1', turnNo: 3);
  }

  RestoreResult? restoreResult;
  Object? restoreError;
  String? restoredName;

  @override
  Future<RestoreResult> restoreCheckpoint(String id, String name) async {
    if (restoreError != null) throw restoreError!;
    restoredName = name;
    return restoreResult ?? RestoreResult(name: name, rewoundToTurn: 2);
  }

  RunGoal? goal;
  Object? goalError;
  String? setGoalText;
  bool setGoalClear = false;
  int? setGoalIterations;

  @override
  Future<RunGoal?> runGoal(String id) async {
    if (goalError != null) throw goalError!;
    return goal;
  }

  @override
  Future<RunGoal?> setRunGoal(String id,
      {String? text, bool clear = false, int? maxIterations}) async {
    if (goalError != null) throw goalError!;
    setGoalText = text;
    setGoalClear = clear;
    setGoalIterations = maxIterations;
    return goal;
  }

  BackgroundTask? startedTask;
  String? startedPrompt;
  List<BackgroundTask> bgTasks = [];
  final Map<String, BackgroundTask> bgTaskById = {};
  Object? bgError;

  @override
  Future<BackgroundTask> startBackgroundTask(
      String id, String prompt) async {
    if (bgError != null) throw bgError!;
    startedPrompt = prompt;
    return startedTask ??
        const BackgroundTask(
            id: 'bg-1', status: 'running', label: 'x', runId: 'r1');
  }

  @override
  Future<List<BackgroundTask>> backgroundTasks(String id) async {
    if (bgError != null) throw bgError!;
    return bgTasks;
  }

  @override
  Future<BackgroundTask> backgroundTask(String taskId) async {
    if (bgError != null) throw bgError!;
    final t = bgTaskById[taskId];
    if (t == null) throw PantheonApiException(404, 'unknown task');
    return t;
  }
}

class _FakeHost implements SlashCommandHost {
  final _FakeApi _api;
  _FakeHost(this._api);

  List<ChatCommand> commands = ChatCommand.fallbackChatCommands;
  String runId = 'r1';

  final List<String> toasts = [];
  final List<Object> errors = [];
  final List<SlashChatMessage> messages = [];
  String? copied;
  bool openedApprovals = false;
  bool openedTeams = false;
  bool openedSessions = false;
  String? openedRun;
  String? openedSwarm;
  UsageStats? statsShown;
  List<Checkpoint>? checkpointsShown;
  List<BackgroundTask>? bgTasksShown;
  BackgroundTask? bgTaskShown;
  final List<String> steered = [];
  String? usedTeamId;
  String? usedTeamTask;
  String? promptAnswer;
  bool promptAllowEmpty = false;

  bool confirmAnswer = true;
  final List<String> confirmTitles = [];
  String? confirmLabel;
  bool? confirmDestructive;

  String? composerText;
  int hideLastTurnCalls = 0;
  int clearTranscriptCalls = 0;
  final List<int> hideTurnsAfterCalls = [];

  @override
  PantheonApi get api => _api;

  @override
  List<ChatCommand> get slashCommands => commands;

  @override
  void showToast(String message) => toasts.add(message);

  @override
  void showError(Object e) => errors.add(e);

  @override
  Future<void> openApprovals() async => openedApprovals = true;

  @override
  Future<void> openTeams() async => openedTeams = true;

  @override
  Future<void> openSessions() async => openedSessions = true;

  @override
  Future<void> openRun(String id) async => openedRun = id;

  @override
  Future<void> openSwarm(String swarmId) async => openedSwarm = swarmId;

  @override
  Future<void> showStatsSheet(UsageStats stats) async => statsShown = stats;

  @override
  Future<void> showCheckpointsSheet(List<Checkpoint> checkpoints) async =>
      checkpointsShown = checkpoints;

  @override
  Future<void> showBackgroundTasksSheet(List<BackgroundTask> tasks) async =>
      bgTasksShown = tasks;

  @override
  Future<void> showBackgroundTaskSheet(BackgroundTask task) async =>
      bgTaskShown = task;

  @override
  Future<void> steerSend(String text) async => steered.add(text);

  @override
  Future<String?> promptFor(String title,
      {bool allowEmpty = false}) async {
    promptAllowEmpty = allowEmpty;
    return promptAnswer;
  }

  @override
  Future<bool> confirm(String title, String body,
          {String confirmLabel = 'Confirm',
          bool destructive = false}) async {
    confirmTitles.add(title);
    this.confirmLabel = confirmLabel;
    confirmDestructive = destructive;
    return confirmAnswer;
  }

  @override
  void setComposerText(String text) => composerText = text;

  @override
  void hideLastTurn() => hideLastTurnCalls++;

  @override
  void clearTranscriptView() => clearTranscriptCalls++;

  @override
  void hideTurnsAfter(int turnNo) => hideTurnsAfterCalls.add(turnNo);

  @override
  List<SlashChatMessage> get chatMessages => messages;

  @override
  Future<void> copyText(String text) async => copied = text;

  @override
  Future<void> useTeam(String id, String? task) async {
    usedTeamId = id;
    usedTeamTask = task;
  }
}

Approval _approval(String id) =>
    Approval(id: id, runId: 'r1', runCreatedMs: 0);

void main() {
  group('ChatCommand catalog', () {
    test('help output lists exactly the curated set', () {
      // /help renders the curated list verbatim, so pin it here.
      final names =
          ChatCommand.fallbackChatCommands.map((c) => c.name).toList();
      expect(names, [
        'new',
        'title',
        'model',
        'reasoning',
        'todos',
        'compress',
        'export',
        'fork',
        'cancel',
        'mode',
        'clear',
        'help',
        'approvals',
        'approve',
        'deny',
        'steer',
        'remember',
        'learn',
        'team',
        'swarm',
        'yank',
        'history',
        'runs',
        'stats',
        'sessions',
        'resume',
        'undo',
        'reset',
        'checkpoint',
        'checkpoints',
        'restore',
        'goal',
        'btw',
        'bg',
      ]);
    });

    test('mergeWithMobile appends cancel/mode to the backend list', () {
      final merged = ChatCommand.mergeWithMobile([
        const ChatCommand(name: 'yank', desc: 'copy last answer'),
        const ChatCommand(name: 'stats', desc: 'usage stats'),
      ]);
      expect(
          merged.map((c) => c.name), ['yank', 'stats', 'cancel', 'mode']);
    });

    test('mergeWithMobile never duplicates a backend-listed mobile command',
        () {
      final merged = ChatCommand.mergeWithMobile([
        const ChatCommand(name: 'cancel', desc: 'backend desc'),
      ]);
      final cancels = merged.where((c) => c.name == 'cancel').toList();
      expect(cancels, hasLength(1));
      expect(cancels.single.desc, 'backend desc');
      expect(merged.map((c) => c.name), ['cancel', 'mode']);
    });
  });

  group('approve / deny', () {
    test('/approve 1 approves the first pending approval', () async {
      final api = _FakeApi();
      api.pending = [_approval('a1'), _approval('a2')];
      final host = _FakeHost(api);
      await SlashCommandDispatcher(host).dispatch('approve', '1');
      expect(api.decided, [('a1', true)]);
      expect(host.toasts, ['Approved.']);
    });

    test('/deny 2 denies the second pending approval', () async {
      final api = _FakeApi();
      api.pending = [_approval('a1'), _approval('a2')];
      final host = _FakeHost(api);
      await SlashCommandDispatcher(host).dispatch('deny', '2');
      expect(api.decided, [('a2', false)]);
      expect(host.toasts, ['Denied.']);
    });

    test('out-of-range index toasts instead of deciding', () async {
      final api = _FakeApi();
      api.pending = [_approval('a1'), _approval('a2')];
      final host = _FakeHost(api);
      await SlashCommandDispatcher(host).dispatch('approve', '9');
      expect(api.decided, isEmpty);
      expect(host.toasts, ['Only 2 pending approvals.']);
    });

    test('empty pending list toasts instead of deciding', () async {
      final api = _FakeApi();
      final host = _FakeHost(api);
      await SlashCommandDispatcher(host).dispatch('deny', '1');
      expect(api.decided, isEmpty);
      expect(host.toasts, ['No pending approvals.']);
    });

    test('non-numeric index shows usage', () async {
      final api = _FakeApi();
      final host = _FakeHost(api);
      await SlashCommandDispatcher(host).dispatch('approve', 'abc');
      expect(api.decided, isEmpty);
      expect(host.toasts, ['Usage: /approve <n>']);
    });

    test('no arg opens the Approvals screen', () async {
      final api = _FakeApi();
      final host = _FakeHost(api);
      await SlashCommandDispatcher(host).dispatch('approve', '');
      await SlashCommandDispatcher(host).dispatch('deny', '');
      expect(host.openedApprovals, isTrue);
      expect(api.decided, isEmpty);
    });
  });

  group('yank', () {
    const convo = [
      SlashChatMessage(role: 'user', content: 'hi'),
      SlashChatMessage(role: 'assistant', content: 'hello there'),
    ];

    test('/yank copies the last assistant message', () async {
      final api = _FakeApi();
      final host = _FakeHost(api)..messages.addAll(convo);
      await SlashCommandDispatcher(host).dispatch('yank', '');
      expect(host.copied, 'hello there');
      expect(host.toasts, ['Copied.']);
    });

    test('/yank 2 copies the second code block', () async {
      final api = _FakeApi();
      final host = _FakeHost(api)
        ..messages.add(SlashChatMessage(
            role: 'assistant',
            content: 'first:\n```dart\nprint(1);\n```\nsecond:\n```dart\nprint(2);\n```'));
      await SlashCommandDispatcher(host).dispatch('yank', '2');
      expect(host.copied, 'print(2);');
      expect(host.toasts, ['Copied code block 2.']);
    });

    test('out-of-range block index toasts', () async {
      final api = _FakeApi();
      final host = _FakeHost(api)
        ..messages.add(const SlashChatMessage(
            role: 'assistant', content: 'only:\n```\nx\n```'));
      await SlashCommandDispatcher(host).dispatch('yank', '5');
      expect(host.copied, isNull);
      expect(host.toasts, ['That message has 1 code block.']);
    });

    test('no assistant message toasts', () async {
      final api = _FakeApi();
      final host = _FakeHost(api)
        ..messages.add(const SlashChatMessage(role: 'user', content: 'hi'));
      await SlashCommandDispatcher(host).dispatch('yank', '');
      expect(host.copied, isNull);
      expect(host.toasts, ['Nothing to yank yet.']);
    });
  });

  group('memory', () {
    test('/remember stores a plain memory', () async {
      final api = _FakeApi();
      final host = _FakeHost(api);
      await SlashCommandDispatcher(host).dispatch('remember', 'the sky is blue');
      expect(api.memoryText, 'the sky is blue');
      expect(api.memoryKind, isNull);
      expect(host.toasts, ['Remembered.']);
    });

    test('/learn stores a lesson via the lesson kind', () async {
      final api = _FakeApi();
      final host = _FakeHost(api);
      await SlashCommandDispatcher(host)
          .dispatch('learn', 'always verify before claiming done');
      // The dashboard namespaces keys as {kind}:{key}; `lesson`
      // matches the TUI's lesson:{slug} convention.
      expect(api.memoryText, 'always verify before claiming done');
      expect(api.memoryKind, 'lesson');
      expect(host.toasts, ['Lesson saved.']);
    });
  });

  group('navigation commands', () {
    test('/approvals opens the Approvals screen', () async {
      final host = _FakeHost(_FakeApi());
      await SlashCommandDispatcher(host).dispatch('approvals', '');
      expect(host.openedApprovals, isTrue);
    });

    test('/history, /runs and /sessions open the runs list', () async {
      for (final cmd in ['history', 'runs', 'sessions']) {
        final host = _FakeHost(_FakeApi());
        await SlashCommandDispatcher(host).dispatch(cmd, '');
        expect(host.openedSessions, isTrue, reason: '/$cmd');
      }
    });

    test('/resume <id> opens that session', () async {
      final host = _FakeHost(_FakeApi());
      await SlashCommandDispatcher(host).dispatch('resume', 'abc123');
      expect(host.openedRun, 'abc123');
    });

    test('/resume without an id shows usage', () async {
      final host = _FakeHost(_FakeApi());
      await SlashCommandDispatcher(host).dispatch('resume', '');
      expect(host.openedRun, isNull);
      expect(host.toasts, ['Usage: /resume <id>']);
    });

    test('/stats shows the stats sheet', () async {
      final host = _FakeHost(_FakeApi());
      await SlashCommandDispatcher(host).dispatch('stats', '');
      expect(host.statsShown, isNotNull);
      expect(host.statsShown!.totals.calls, 3);
    });

    test('/steer forwards text to the steer path', () async {
      final host = _FakeHost(_FakeApi());
      await SlashCommandDispatcher(host).dispatch('steer', 'go left');
      expect(host.steered, ['go left']);
    });

    test('/team with no id opens the teams browser', () async {
      final host = _FakeHost(_FakeApi());
      await SlashCommandDispatcher(host).dispatch('team', '');
      expect(host.openedTeams, isTrue);
      expect(host.usedTeamId, isNull);
    });

    test('/team <id> [task] spawns the team', () async {
      final host = _FakeHost(_FakeApi());
      await SlashCommandDispatcher(host).dispatch('team', 't1 do the thing');
      expect(host.usedTeamId, 't1');
      expect(host.usedTeamTask, 'do the thing');
    });

    test('/swarm launches with the launcher defaults', () async {
      final api = _FakeApi();
      final host = _FakeHost(api);
      await SlashCommandDispatcher(host).dispatch('swarm', 'explore the api');
      expect(api.swarmTask, 'explore the api');
      expect(api.swarmMode, 'count');
      expect(api.swarmCount, 4);
      expect(api.swarmJudge, isTrue);
      expect(host.openedSwarm, 's1');
      expect(host.toasts, ['Swarm launched.']);
    });
  });

  group('unknown command', () {
    test('unknown /bogus keeps the friendly toast', () async {
      final host = _FakeHost(_FakeApi());
      await SlashCommandDispatcher(host).dispatch('bogus', '');
      expect(host.toasts, ['Unknown command /bogus — try /help.']);
    });
  });

  group('undo', () {
    test('confirmed undo rewinds, hides the turn, restores the draft',
        () async {
      final api = _FakeApi()
        ..rewindResult =
            const RewindResult(rewoundTurnId: 't9', draft: 'my message');
      final host = _FakeHost(api);
      await SlashCommandDispatcher(host).dispatch('undo', '');
      expect(host.confirmTitles, ['Undo last turn?']);
      expect(host.confirmDestructive, isTrue);
      expect(host.hideLastTurnCalls, 1);
      expect(host.composerText, 'my message');
      expect(host.toasts, ['Undone — your message is back in the composer.']);
      expect(host.errors, isEmpty);
    });

    test('declined confirm does nothing', () async {
      final api = _FakeApi()
        ..rewindResult =
            const RewindResult(rewoundTurnId: 't9', draft: 'x');
      final host = _FakeHost(api)..confirmAnswer = false;
      await SlashCommandDispatcher(host).dispatch('undo', '');
      expect(host.hideLastTurnCalls, 0);
      expect(host.composerText, isNull);
      expect(host.toasts, isEmpty);
    });

    test('409 while a turn runs toasts to wait', () async {
      final api = _FakeApi()
        ..rewindError = PantheonTurnInFlightException('in flight');
      final host = _FakeHost(api);
      await SlashCommandDispatcher(host).dispatch('undo', '');
      expect(host.toasts, ['Wait for the turn to finish.']);
      expect(host.errors, isEmpty);
      expect(host.hideLastTurnCalls, 0);
    });

    test('400 with no turn toasts accordingly', () async {
      final api = _FakeApi()
        ..rewindError = PantheonApiException(400, 'NO_TURN');
      final host = _FakeHost(api);
      await SlashCommandDispatcher(host).dispatch('undo', '');
      expect(host.toasts, ['No finished turn to undo.']);
      expect(host.errors, isEmpty);
    });

    test('stale backend shows the upgrade toast, not a raw error', () async {
      final api = _FakeApi()
        ..rewindError = PantheonStaleBackendException(404, 'gone');
      final host = _FakeHost(api);
      await SlashCommandDispatcher(host).dispatch('undo', '');
      expect(host.errors, isEmpty);
      expect(host.toasts,
          ['This needs a newer dashboard — update Pantheon and try again.']);
    });
  });

  group('reset', () {
    test('reset clears the local view and keeps session/title/history',
        () async {
      final api = _FakeApi()..resetCanceled = true;
      final host = _FakeHost(api);
      await SlashCommandDispatcher(host).dispatch('reset', '');
      expect(host.clearTranscriptCalls, 1);
      expect(host.toasts.single, contains('history are kept'));
      expect(host.toasts.single, contains('canceled'));
    });

    test('reset without a canceled turn still toasts the kept state',
        () async {
      final host = _FakeHost(_FakeApi());
      await SlashCommandDispatcher(host).dispatch('reset', '');
      expect(host.clearTranscriptCalls, 1);
      expect(host.toasts, ['Reset — session, title, and history are kept.']);
    });
  });

  group('checkpoint / checkpoints', () {
    test('/checkpoint <name> saves with that name', () async {
      final api = _FakeApi()
        ..createdCheckpoint = const Checkpoint(name: 'v1', turnNo: 4);
      final host = _FakeHost(api);
      await SlashCommandDispatcher(host).dispatch('checkpoint', 'v1');
      expect(api.lastCheckpointName, 'v1');
      expect(host.toasts, ["Checkpoint 'v1' saved."]);
    });

    test('empty prompt name means server auto-name', () async {
      final api = _FakeApi()
        ..createdCheckpoint = const Checkpoint(name: 'auto-7', turnNo: 2);
      final host = _FakeHost(api)..promptAnswer = '';
      await SlashCommandDispatcher(host).dispatch('checkpoint', '');
      expect(host.promptAllowEmpty, isTrue);
      expect(api.lastCheckpointName, isNull);
      expect(host.toasts, ["Checkpoint 'auto-7' saved."]);
    });

    test('canceled prompt does nothing', () async {
      final api = _FakeApi();
      final host = _FakeHost(api)..promptAnswer = null;
      await SlashCommandDispatcher(host).dispatch('checkpoint', '');
      expect(api.lastCheckpointName, isNull);
      expect(host.toasts, isEmpty);
    });

    test('/checkpoints lists them in a sheet', () async {
      final api = _FakeApi()
        ..checkpointList = const [
          Checkpoint(name: 'v1', turnNo: 1),
          Checkpoint(name: 'v2', turnNo: 3, restorable: false),
        ];
      final host = _FakeHost(api);
      await SlashCommandDispatcher(host).dispatch('checkpoints', '');
      expect(host.checkpointsShown!.map((c) => c.name), ['v1', 'v2']);
      expect(host.toasts, isEmpty);
    });

    test('/checkpoints with none toasts', () async {
      final host = _FakeHost(_FakeApi());
      await SlashCommandDispatcher(host).dispatch('checkpoints', '');
      expect(host.checkpointsShown, isNull);
      expect(host.toasts, ['No checkpoints yet.']);
    });
  });

  group('restore', () {
    test('/restore <name> hides later turns and toasts', () async {
      final api = _FakeApi()
        ..restoreResult = const RestoreResult(name: 'v1', rewoundToTurn: 3);
      final host = _FakeHost(api);
      await SlashCommandDispatcher(host).dispatch('restore', 'v1');
      expect(api.restoredName, 'v1');
      expect(host.hideTurnsAfterCalls, [3]);
      expect(host.toasts, ["Restored 'v1' — rewound to turn 3."]);
    });

    test('bare /restore prompts for the name', () async {
      final api = _FakeApi();
      final host = _FakeHost(api)..promptAnswer = 'v2';
      await SlashCommandDispatcher(host).dispatch('restore', '');
      expect(api.restoredName, 'v2');
      expect(host.hideTurnsAfterCalls, [2]);
    });

    test('unknown checkpoint surfaces the server error', () async {
      final api = _FakeApi()
        ..restoreError = PantheonApiException(404, 'CHECKPOINT_NOT_FOUND');
      final host = _FakeHost(api);
      await SlashCommandDispatcher(host).dispatch('restore', 'nope');
      expect(host.errors.single.toString(), contains('CHECKPOINT_NOT_FOUND'));
      expect(host.hideTurnsAfterCalls, isEmpty);
    });

    test('409 while a turn runs toasts to wait', () async {
      final api = _FakeApi()
        ..restoreError = PantheonTurnInFlightException('in flight');
      final host = _FakeHost(api);
      await SlashCommandDispatcher(host).dispatch('restore', 'v1');
      expect(host.toasts, ['Wait for the turn to finish.']);
      expect(host.errors, isEmpty);
    });
  });

  group('goal', () {
    test('bare /goal shows the goal and iteration usage', () async {
      final api = _FakeApi()
        ..goal = const RunGoal(
            text: 'ship it', iterationsUsed: 3, maxIterations: 10);
      final host = _FakeHost(api);
      await SlashCommandDispatcher(host).dispatch('goal', '');
      expect(host.toasts, ['Goal: ship it · 3/10 iterations used.']);
    });

    test('bare /goal with no cap omits the cap', () async {
      final api = _FakeApi()
        ..goal = const RunGoal(text: 'ship it', iterationsUsed: 3);
      final host = _FakeHost(api);
      await SlashCommandDispatcher(host).dispatch('goal', '');
      expect(host.toasts, ['Goal: ship it · 3 iterations used.']);
    });

    test('bare /goal with no goal toasts', () async {
      final host = _FakeHost(_FakeApi());
      await SlashCommandDispatcher(host).dispatch('goal', '');
      expect(host.toasts, ['No goal set.']);
    });

    test('/goal <text> sets the goal', () async {
      final api = _FakeApi();
      final host = _FakeHost(api);
      await SlashCommandDispatcher(host).dispatch('goal', 'write the tests');
      expect(api.setGoalText, 'write the tests');
      expect(api.setGoalClear, isFalse);
      expect(host.toasts, ['Goal set.']);
    });

    test('/goal clear clears the goal', () async {
      final api = _FakeApi();
      final host = _FakeHost(api);
      await SlashCommandDispatcher(host).dispatch('goal', 'clear');
      expect(api.setGoalClear, isTrue);
      expect(api.setGoalText, isNull);
      expect(host.toasts, ['Goal cleared.']);
    });

    test('/goal iterations <n> retunes the cap', () async {
      final api = _FakeApi();
      final host = _FakeHost(api);
      await SlashCommandDispatcher(host).dispatch('goal', 'iterations 5');
      expect(api.setGoalIterations, 5);
      expect(host.toasts, ['Goal cap set to 5 iterations.']);
    });

    test('/goal iterations <bad> shows usage', () async {
      final api = _FakeApi();
      final host = _FakeHost(api);
      await SlashCommandDispatcher(host).dispatch('goal', 'iterations x');
      expect(api.setGoalIterations, isNull);
      expect(host.toasts.single, contains('Usage: /goal'));
      await SlashCommandDispatcher(host).dispatch('goal', 'iterations 0');
      expect(host.toasts.last, contains('Usage: /goal'));
    });

    test('retune with no goal surfaces the server error', () async {
      final api = _FakeApi()..goalError = PantheonApiException(404, 'NO_GOAL');
      final host = _FakeHost(api);
      await SlashCommandDispatcher(host).dispatch('goal', 'iterations 5');
      expect(host.errors.single.toString(), contains('NO_GOAL'));
    });
  });

  group('btw', () {
    test('/btw <prompt> starts a background task', () async {
      final api = _FakeApi()
        ..startedTask = const BackgroundTask(
            id: 'bg-3', status: 'running', label: 'research', runId: 'r1');
      final host = _FakeHost(api);
      await SlashCommandDispatcher(host).dispatch('btw', 'research the api');
      expect(api.startedPrompt, 'research the api');
      expect(host.toasts, ['Background task bg-3 started.']);
    });

    test('bare /btw prompts for the task', () async {
      final api = _FakeApi();
      final host = _FakeHost(api)..promptAnswer = 'dig into logs';
      await SlashCommandDispatcher(host).dispatch('btw', '');
      expect(api.startedPrompt, 'dig into logs');
    });

    test('canceled prompt does nothing', () async {
      final api = _FakeApi();
      final host = _FakeHost(api)..promptAnswer = null;
      await SlashCommandDispatcher(host).dispatch('btw', '');
      expect(api.startedPrompt, isNull);
      expect(host.toasts, isEmpty);
    });
  });

  group('bg', () {
    test('bare /bg lists tasks in a sheet', () async {
      final api = _FakeApi()
        ..bgTasks = const [
          BackgroundTask(
              id: 'bg-1', status: 'running', label: 'research', runId: 'r1'),
          BackgroundTask(
              id: 'bg-2', status: 'done', label: 'fetch', runId: 'r1'),
        ];
      final host = _FakeHost(api);
      await SlashCommandDispatcher(host).dispatch('bg', '');
      expect(host.bgTasksShown!.map((t) => t.id), ['bg-1', 'bg-2']);
      expect(host.toasts, isEmpty);
    });

    test('bare /bg with none toasts', () async {
      final host = _FakeHost(_FakeApi());
      await SlashCommandDispatcher(host).dispatch('bg', '');
      expect(host.bgTasksShown, isNull);
      expect(host.toasts, ['No background tasks.']);
    });

    test('/bg 1 accepts the bare number and shows output', () async {
      final api = _FakeApi();
      const task = BackgroundTask(
          id: 'bg-1',
          status: 'done',
          label: 'fetch',
          runId: 'r1',
          output: 'all done');
      api.bgTaskById['bg-1'] = task;
      final host = _FakeHost(api);
      await SlashCommandDispatcher(host).dispatch('bg', '1');
      expect(host.bgTaskShown, task);
      expect(host.toasts, isEmpty);
    });

    test('/bg bg-2 on a running task toasts still-running', () async {
      final api = _FakeApi();
      api.bgTaskById['bg-2'] = const BackgroundTask(
          id: 'bg-2', status: 'running', label: 'research', runId: 'r1');
      final host = _FakeHost(api);
      await SlashCommandDispatcher(host).dispatch('bg', 'bg-2');
      expect(host.bgTaskShown, isNull);
      expect(host.toasts, ['bg-2 is still running.']);
    });

    test('task lookup failure surfaces the error', () async {
      final api = _FakeApi()..bgError = PantheonApiException(404, 'nope');
      final host = _FakeHost(api);
      await SlashCommandDispatcher(host).dispatch('bg', '');
      expect(host.errors, isNotEmpty);
    });
  });
}
