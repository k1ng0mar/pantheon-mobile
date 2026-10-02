import '../models/models.dart';
import 'pantheon_api.dart';

/// One chat message for slash-command purposes: role + text.
class SlashChatMessage {
  final String? role;
  final String content;
  const SlashChatMessage({this.role, required this.content});
}

/// UI effects a chat slash command can trigger. Implemented by the
/// session detail screen; tests use a fake.
abstract class SlashCommandHost {
  PantheonApi get api;

  /// The id of the session the chat belongs to.
  String get runId;

  /// The curated command list (`GET /api/commands?surface=chat` merged
  /// with the mobile-only commands, or the hardcoded fallback).
  List<ChatCommand> get slashCommands;

  void showToast(String message);
  void showError(Object e);
  Future<void> openApprovals();
  Future<void> openTeams();
  Future<void> openSessions();
  Future<void> openRun(String id);
  Future<void> openSwarm(String swarmId);
  Future<void> showStatsSheet(UsageStats stats);
  Future<void> showCheckpointsSheet(List<Checkpoint> checkpoints);
  Future<void> showBackgroundTasksSheet(List<BackgroundTask> tasks);
  Future<void> showBackgroundTaskSheet(BackgroundTask task);

  /// Steer the running turn with [text]; a normal message when idle.
  Future<void> steerSend(String text);

  /// Text prompt; null on cancel. With [allowEmpty], saving empty
  /// returns '' instead of null.
  Future<String?> promptFor(String title, {bool allowEmpty = false});

  /// Destructive-action confirm sheet; true when confirmed.
  Future<bool> confirm(String title, String body,
      {String confirmLabel = 'Confirm', bool destructive = false});

  List<SlashChatMessage> get chatMessages;
  Future<void> copyText(String text);

  /// Replace the composer text (used to restore a rewound draft).
  void setComposerText(String text);

  /// Hide the last user turn (the trailing user message and everything
  /// after it) from the local transcript view.
  void hideLastTurn();

  /// Clear the local transcript view (server state is untouched beyond
  /// what the reset already did).
  void clearTranscriptView();

  /// Hide every turn after [turnNo] (1-based, counted by user messages)
  /// from the local transcript view.
  void hideTurnsAfter(int turnNo);

  /// `POST /api/teams/:id/use` (+ optional task) and open the spawned
  /// session.
  Future<void> useTeam(String id, String? task);
}

/// Dispatches the chat slash commands that have a real mobile path.
/// The session screen's own `_runSlash` switch owns the older command
/// set (new/title/model/…) and delegates everything else here.
class SlashCommandDispatcher {
  final SlashCommandHost host;
  const SlashCommandDispatcher(this.host);

  Future<void> dispatch(String cmd, String arg) async {
    switch (cmd) {
      case 'approvals':
        await host.openApprovals();
        break;
      case 'approve':
        await _decide(true, arg);
        break;
      case 'deny':
        await _decide(false, arg);
        break;
      case 'steer':
        await _steer(arg);
        break;
      case 'remember':
        await _remember(arg);
        break;
      case 'learn':
        await _learn(arg);
        break;
      case 'team':
        await _team(arg);
        break;
      case 'swarm':
        await _swarm(arg);
        break;
      case 'yank':
        await _yank(arg);
        break;
      case 'history':
      case 'runs':
      case 'sessions':
        await host.openSessions();
        break;
      case 'stats':
        await _stats();
        break;
      case 'resume':
        await _resume(arg);
        break;
      case 'undo':
        await _undo();
        break;
      case 'reset':
        await _reset();
        break;
      case 'checkpoint':
        await _checkpoint(arg);
        break;
      case 'checkpoints':
        await _checkpoints();
        break;
      case 'restore':
        await _restore(arg);
        break;
      case 'goal':
        await _goal(arg);
        break;
      case 'btw':
        await _btw(arg);
        break;
      case 'bg':
        await _bg(arg);
        break;
      default:
        host.showToast('Unknown command /$cmd — try /help.');
    }
  }

  /// Runs [work], mapping a stale backend to the friendly upgrade
  /// toast (same pattern as the approvals tiers) and everything else
  /// to the error toast.
  Future<void> _guarded(Future<void> Function() work) async {
    try {
      await work();
    } on PantheonStaleBackendException catch (e) {
      host.showToast(e.toString());
    } catch (e) {
      host.showError(e);
    }
  }

  /// `/approve <n>` / `/deny <n>`: decide the Nth (1-based) pending
  /// approval. No arg opens the Approvals screen instead.
  Future<void> _decide(bool grant, String arg) async {
    final verb = grant ? 'approve' : 'deny';
    if (arg.isEmpty) {
      await host.openApprovals();
      return;
    }
    final n = int.tryParse(arg);
    if (n == null || n < 1) {
      host.showToast('Usage: /$verb <n>');
      return;
    }
    try {
      final pending = await host.api.approvals();
      if (pending.isEmpty) {
        host.showToast('No pending approvals.');
        return;
      }
      if (n > pending.length) {
        host.showToast(
            'Only ${pending.length} pending approval${pending.length == 1 ? '' : 's'}.');
        return;
      }
      final a = pending[n - 1];
      await host.api.decideApproval(a.id, grant);
      host.showToast(grant ? 'Approved.' : 'Denied.');
    } catch (e) {
      host.showError(e);
    }
  }

  Future<void> _steer(String arg) async {
    final text = await _argOrPrompt(arg, 'Steer the running turn');
    if (text == null) return;
    await host.steerSend(text);
  }

  Future<void> _remember(String arg) async {
    final text = await _argOrPrompt(arg, 'Remember');
    if (text == null) return;
    try {
      await host.api.addMemory(text: text);
      host.showToast('Remembered.');
    } catch (e) {
      host.showError(e);
    }
  }

  Future<void> _learn(String arg) async {
    final text = await _argOrPrompt(arg, 'Learn');
    if (text == null) return;
    try {
      // The dashboard namespaces memory keys as `{kind}:{key}`; `lesson`
      // is the real convention — it matches the TUI's `lesson:{slug}`
      // keys for /learn lessons.
      await host.api.addMemory(text: text, kind: 'lesson');
      host.showToast('Lesson saved.');
    } catch (e) {
      host.showError(e);
    }
  }

  /// `/team <id> [task]` spawns the team (with the task when given);
  /// bare `/team` opens the teams/experts browser.
  Future<void> _team(String arg) async {
    if (arg.isEmpty) {
      await host.openTeams();
      return;
    }
    final space = arg.indexOf(RegExp(r'\s'));
    final id = space < 0 ? arg : arg.substring(0, space);
    final rest = space < 0 ? '' : arg.substring(space + 1).trim();
    await host.useTeam(id, rest.isEmpty ? null : rest);
  }

  Future<void> _swarm(String arg) async {
    final task = await _argOrPrompt(arg, 'New swarm');
    if (task == null) return;
    try {
      // Same defaults as the swarm launcher UI: N subagents, judge on.
      final j = await host.api.createSwarm(
          task: task, mode: 'count', subagentCount: 4, judge: true);
      final id = j['swarm_id']?.toString();
      if (id == null || id.isEmpty) {
        host.showToast('Swarm launched but returned no id.');
        return;
      }
      host.showToast('Swarm launched.');
      await host.openSwarm(id);
    } catch (e) {
      host.showError(e);
    }
  }

  /// `/yank` copies the last assistant message; `/yank <n>` copies its
  /// Nth fenced code block.
  Future<void> _yank(String arg) async {
    SlashChatMessage? last;
    for (final m in host.chatMessages.reversed) {
      if (m.role == 'assistant') {
        last = m;
        break;
      }
    }
    if (last == null) {
      host.showToast('Nothing to yank yet.');
      return;
    }
    if (arg.isEmpty) {
      await host.copyText(last.content);
      host.showToast('Copied.');
      return;
    }
    final n = int.tryParse(arg);
    final blocks = _codeBlocks(last.content);
    if (n == null || n < 1) {
      host.showToast('Usage: /yank [n]');
      return;
    }
    if (n > blocks.length) {
      host.showToast(
          'That message has ${blocks.length} code block${blocks.length == 1 ? '' : 's'}.');
      return;
    }
    await host.copyText(blocks[n - 1]);
    host.showToast('Copied code block $n.');
  }

  static final _fence = RegExp(r'```[^\n]*\n([\s\S]*?)```');

  static List<String> _codeBlocks(String text) => [
        for (final m in _fence.allMatches(text)) m.group(1)!.trimRight(),
      ];

  Future<void> _stats() async {
    try {
      await host.showStatsSheet(await host.api.stats());
    } catch (e) {
      host.showError(e);
    }
  }

  Future<void> _resume(String arg) async {
    if (arg.isEmpty) {
      host.showToast('Usage: /resume <id>');
      return;
    }
    await host.openRun(arg);
  }

  /// `/undo`: confirm (the TUI requires it), then rewind the last
  /// finished turn. The rewound turn is hidden from the local
  /// transcript view and the dropped user message is restored as a
  /// composer draft, mirroring the TUI.
  Future<void> _undo() async {
    final ok = await host.confirm(
      'Undo last turn?',
      'The last turn is dropped and your message is restored as a draft.',
      confirmLabel: 'Undo',
      destructive: true,
    );
    if (!ok) return;
    await _guarded(() async {
      try {
        final res = await host.api.rewindRun(host.runId);
        host.hideLastTurn();
        host.setComposerText(res.draft);
        host.showToast('Undone — your message is back in the composer.');
      } on PantheonTurnInFlightException {
        host.showToast('Wait for the turn to finish.');
      } on PantheonApiException catch (e) {
        if (e.status == 400) {
          // NO_TURN: nothing finished to rewind.
          host.showToast('No finished turn to undo.');
        } else {
          rethrow;
        }
      }
    });
  }

  /// `/reset`: reset the run's transcript. Session, title, and ledger
  /// history are kept server-side; only the local view is cleared.
  Future<void> _reset() async {
    await _guarded(() async {
      final res = await host.api.resetRun(host.runId);
      host.clearTranscriptView();
      host.showToast(res.canceled
          ? 'Reset — the running turn was canceled. Session, title, and history are kept.'
          : 'Reset — session, title, and history are kept.');
    });
  }

  /// `/checkpoint [name]`: save a checkpoint. An empty name means the
  /// server auto-names it.
  Future<void> _checkpoint(String arg) async {
    final name = await _argOrPrompt(arg, 'Checkpoint name', allowEmpty: true);
    if (name == null) return;
    await _guarded(() async {
      final cp = await host.api.createCheckpoint(host.runId,
          name: name.isEmpty ? null : name);
      host.showToast("Checkpoint '${cp.name}' saved.");
    });
  }

  /// `/checkpoints`: list the run's checkpoints.
  Future<void> _checkpoints() async {
    await _guarded(() async {
      final cps = await host.api.runCheckpoints(host.runId);
      if (cps.isEmpty) {
        host.showToast('No checkpoints yet.');
        return;
      }
      await host.showCheckpointsSheet(cps);
    });
  }

  /// `/restore <name>`: restore a checkpoint, hiding every turn after
  /// the rewind target from the local transcript view.
  Future<void> _restore(String arg) async {
    final name = await _argOrPrompt(arg, 'Restore checkpoint');
    if (name == null) return;
    await _guarded(() async {
      try {
        final res = await host.api.restoreCheckpoint(host.runId, name);
        host.hideTurnsAfter(res.rewoundToTurn);
        host.showToast(
            "Restored '${res.name}' — rewound to turn ${res.rewoundToTurn}.");
      } on PantheonTurnInFlightException {
        host.showToast('Wait for the turn to finish.');
      }
    });
  }

  static const _goalUsage =
      'Usage: /goal <text> · /goal clear · /goal iterations <n>';

  /// `/goal`: bare shows the current goal and iteration usage;
  /// `/goal <text>` sets it, `/goal clear` clears it,
  /// `/goal iterations <n>` retunes the cap.
  Future<void> _goal(String arg) async {
    if (arg.isEmpty) {
      await _guarded(() async {
        final goal = await host.api.runGoal(host.runId);
        if (goal == null) {
          host.showToast('No goal set.');
          return;
        }
        final cap = goal.maxIterations;
        host.showToast(cap == null
            ? 'Goal: ${goal.text} · ${goal.iterationsUsed} iterations used.'
            : 'Goal: ${goal.text} · ${goal.iterationsUsed}/$cap iterations used.');
      });
      return;
    }
    final lower = arg.toLowerCase();
    if (lower == 'clear') {
      await _guarded(() async {
        await host.api.setRunGoal(host.runId, clear: true);
        host.showToast('Goal cleared.');
      });
      return;
    }
    final iter = RegExp(r'^iterations\s+(\d+)\s*$').firstMatch(lower);
    if (lower.startsWith('iterations')) {
      final n = iter == null ? 0 : int.parse(iter.group(1)!);
      if (n < 1) {
        host.showToast(_goalUsage);
        return;
      }
      await _guarded(() async {
        await host.api.setRunGoal(host.runId, maxIterations: n);
        host.showToast('Goal cap set to $n iterations.');
      });
      return;
    }
    await _guarded(() async {
      await host.api.setRunGoal(host.runId, text: arg);
      host.showToast('Goal set.');
    });
  }

  /// `/btw <prompt>`: start a by-the-way background task.
  Future<void> _btw(String arg) async {
    final prompt = await _argOrPrompt(arg, 'Background task');
    if (prompt == null) return;
    await _guarded(() async {
      final task = await host.api.startBackgroundTask(host.runId, prompt);
      host.showToast('Background task ${task.id} started.');
    });
  }

  /// `/bg`: list the run's background tasks. `/bg <id>` (accepts
  /// `bg-N` or just `N`) shows the task's full output, or reports that
  /// it is still running.
  Future<void> _bg(String arg) async {
    await _guarded(() async {
      if (arg.isEmpty) {
        final tasks = await host.api.backgroundTasks(host.runId);
        if (tasks.isEmpty) {
          host.showToast('No background tasks.');
          return;
        }
        await host.showBackgroundTasksSheet(tasks);
        return;
      }
      final id = RegExp(r'^\d+$').hasMatch(arg) ? 'bg-$arg' : arg;
      final task = await host.api.backgroundTask(id);
      final out = task.output;
      if (out == null) {
        host.showToast('${task.id} is still running.');
        return;
      }
      await host.showBackgroundTaskSheet(task);
    });
  }

  Future<String?> _argOrPrompt(String arg, String title,
      {bool allowEmpty = false}) async {
    if (arg.isNotEmpty) return arg;
    final t = await host.promptFor(title, allowEmpty: allowEmpty);
    if (t == null) return null;
    final trimmed = t.trim();
    if (trimmed.isEmpty && !allowEmpty) return null;
    return trimmed;
  }
}
