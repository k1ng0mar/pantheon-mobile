import 'dart:async';

import 'package:flutter/material.dart';

import '../models/approval.dart';
import '../models/pantheon_run.dart';
import '../models/todo_item.dart';
import '../services/pantheon_api.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/chips.dart';
import '../widgets/export_sheet.dart';
import '../widgets/forms.dart';
import '../widgets/states.dart';
import '../widgets/todos_sheet.dart';

/// A session as a real chat: transcript bubbles, live polling while the
/// run is active, and a composer that sends into the run via
/// `POST /api/runs/:id/message`. Settled sessions keep their composer:
/// completed/failed/canceled only end the latest turn — the runtime
/// reopens the run when a new message arrives.
///
/// Full state handling: clarify cards (`ask_user`), inline approval
/// banner, stop/queue/steer, slash commands, todos, plan/build mode,
/// context meter.
class SessionDetailScreen extends StatefulWidget {
  final PantheonApi api;
  final String runId;

  const SessionDetailScreen(
      {super.key, required this.api, required this.runId});

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  PantheonRun? _run;
  final List<TranscriptItem> _messages = [];

  /// Optimistic bubbles not yet present in the server transcript.
  /// Reconciled away by [_syncMessages] once the server admits them —
  /// so a replaced queue slot can never leave a phantom bubble.
  final List<TranscriptItem> _pending = [];
  String? _error;
  bool _loading = true;

  final _composer = TextEditingController();
  final _answerCtrl = TextEditingController();
  final _scroll = ScrollController();
  Timer? _poll;
  bool _sending = false;
  bool _atBottom = true;

  /// Approvals parked on this run (inline banner).
  List<Approval> _runApprovals = [];

  /// Open (non-completed) todo count for the header chip.
  int _openTodos = 0;

  /// `provider · model` from the `[model]` config section.
  String? _modelLine;

  /// True when the queued message showing in the detail was set from
  /// this screen — the poller auto-drains it when the turn settles.
  bool _queuedByMe = false;

  static bool _isLive(String status) =>
      status == 'running' || status == 'awaiting_approval';

  /// The composer stays enabled for settled sessions: completed/failed/
  /// canceled mark the end of a turn, not the death of the session — the
  /// runtime reopens the run when a new message arrives.
  static bool _canChat(String status) =>
      _isLive(status) ||
      status == 'completed' ||
      status == 'failed' ||
      status == 'canceled';

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_trackScroll);
    _load(initial: true);
  }

  @override
  void dispose() {
    _poll?.cancel();
    _composer.dispose();
    _answerCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _trackScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    _atBottom = pos.pixels >= pos.maxScrollExtent - 120;
  }

  Future<void> _load({bool initial = false}) async {
    if (initial) setState(() => _loading = true);
    try {
      final run = await widget.api.runDetail(widget.runId);
      if (!mounted) return;
      final todos = await _safeTodos();
      final modelLine = await _safeModelLine();
      final approvals = run.status == 'awaiting_approval'
          ? await _safeRunApprovals()
          : <Approval>[];
      if (!mounted) return;
      setState(() {
        _run = run;
        _pending.clear();
        _messages
          ..clear()
          ..addAll(run.transcript);
        _openTodos = todos.where((t) => !t.done).length;
        _modelLine = modelLine;
        _runApprovals = approvals;
        _error = null;
        _loading = false;
      });
      _syncPolling(run.status);
      if (initial) _jumpToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<List<TodoItem>> _safeTodos() async {
    try {
      return await widget.api.getTodos(widget.runId);
    } catch (_) {
      return [];
    }
  }

  Future<List<Approval>> _safeRunApprovals() async {
    try {
      final all = await widget.api.approvals();
      return all.where((a) => a.runId == widget.runId).toList();
    } catch (_) {
      return [];
    }
  }

  /// `provider · model` from the `[model]` config section; null when
  /// unreadable (the header falls back to the run's own fields).
  Future<String?> _safeModelLine() async {
    try {
      final doc = await widget.api.getConfig();
      final m = doc.values['model'];
      if (m is Map) {
        final p = m['provider']?.toString();
        final mod = m['model']?.toString();
        final parts = [
          if (p != null && p.isNotEmpty) p,
          if (mod != null && mod.isNotEmpty) mod,
        ];
        if (parts.isNotEmpty) return parts.join(' · ');
      }
    } catch (_) {}
    return null;
  }

  Future<void> _refreshRunApprovals() async {
    try {
      final mine = await _safeRunApprovals();
      if (!mounted) return;
      setState(() => _runApprovals = mine);
    } catch (_) {}
  }

  void _syncPolling(String status) {
    final live = _isLive(status);
    if (live && _poll == null) {
      _poll = Timer.periodic(const Duration(seconds: 3), (_) => _pollOnce());
    } else if (!live) {
      _poll?.cancel();
      _poll = null;
    }
  }

  /// Fetch the latest detail and reconcile the transcript.
  Future<void> _pollOnce() async {
    if (!mounted) return;
    try {
      final run = await widget.api.runDetail(widget.runId);
      if (!mounted) return;
      final wasLive = _isLive(_run?.status ?? '');
      final grew = _syncMessages(run.transcript);
      // Always take the fresh run: the queued chip, mode pills, and
      // context meter read from _run, not just its status.
      setState(() => _run = run);
      // Auto-drain a queue this screen set, once the turn settles.
      if (wasLive && !_isLive(run.status) && _queuedByMe) {
        final q = run.queuedMessage;
        _queuedByMe = false;
        if (q != null && q.isNotEmpty) {
          await _drainQueueText(q);
          return;
        }
      }
      // Keep the inline approval banner fresh while parked.
      if (run.status == 'awaiting_approval') {
        await _refreshRunApprovals();
      } else if (_runApprovals.isNotEmpty) {
        setState(() => _runApprovals = []);
      }
      _syncPolling(run.status);
      if (grew && _atBottom) _animateToBottom();
    } catch (_) {
      // Polling is best-effort; the next tick retries.
    }
  }

  static String _msgKey(TranscriptItem t) =>
      '${t.role}|${t.type}|${t.content}';

  /// Reconcile [_messages] with the server transcript: drop optimistic
  /// items the server has admitted, keep the rest on top. Returns true
  /// when the visible list grew (new server items arrived).
  bool _syncMessages(List<TranscriptItem> fresh) {
    final keys = {for (final t in fresh) _msgKey(t)};
    _pending.removeWhere((t) => keys.contains(_msgKey(t)));
    final merged = [...fresh, ..._pending];
    final cur = _messages;
    final same = merged.length == cur.length &&
        Iterable.generate(merged.length).every((i) =>
            merged[i].role == cur[i].role &&
            merged[i].type == cur[i].type &&
            merged[i].content == cur[i].content);
    if (same) return false;
    final grew = merged.length > cur.length;
    setState(() {
      _messages
        ..clear()
        ..addAll(merged);
    });
    return grew;
  }

  void _addOptimistic(TranscriptItem t) {
    _pending.add(t);
    setState(() => _messages.add(t));
  }

  void _removeOptimistic(TranscriptItem t) {
    _pending.remove(t);
    setState(() => _messages.remove(t));
  }

  /// Send a queued message as a normal turn now that the run settled.
  Future<void> _drainQueueText(String text) async {
    try {
      await widget.api.sendRunMessage(widget.runId, text);
      // Idempotent: the backend may already have consumed the slot.
      await widget.api.clearQueue(widget.runId);
      _poll ??=
          Timer.periodic(const Duration(seconds: 3), (_) => _pollOnce());
      await _pollOnce();
    } on PantheonTurnInFlightException {
      // A new turn started before we drained; retry on the next settle.
      _queuedByMe = true;
    } catch (_) {}
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty || _sending) return;
    if (text.startsWith('/')) {
      _composer.clear();
      await _runSlash(text);
      return;
    }
    final run = _run;
    if (run == null || !_canChat(run.status)) return;
    setState(() => _sending = true);
    _composer.clear();
    final optimistic =
        TranscriptItem(type: 'message', role: 'user', content: text);
    _addOptimistic(optimistic);
    _animateToBottom();
    try {
      final result = await widget.api.sendRunMessage(run.id, text);
      if (result.queued || result.steered) {
        _queuedByMe = true;
        if (!mounted) return;
        toast(
            context,
            result.steered
                ? 'Steering the running turn…'
                : 'Queued — sends when the turn settles.');
      }
      // Pull the authoritative transcript right away, and make sure the
      // poller is running: a settled session just reopened, so replies
      // stream in from here.
      _poll ??=
          Timer.periodic(const Duration(seconds: 3), (_) => _pollOnce());
      await _pollOnce();
    } on PantheonTurnInFlightException {
      if (!mounted) return;
      _removeOptimistic(optimistic);
      await _turnBusySheet(text);
    } on PantheonRunFinishedException {
      if (!mounted) return;
      _removeOptimistic(optimistic);
      await _load();
      toast(context, 'This session could not be reopened.');
    } catch (e) {
      if (!mounted) return;
      _removeOptimistic(optimistic);
      toastError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// A turn is already running: offer queue / steer / dismiss.
  Future<void> _turnBusySheet(String text) async {
    final choice = await showPSheet<String>(
      context,
      SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SheetHandle(),
              const SizedBox(height: 8),
              const Text('A turn is already running',
                  style: PT.sectionTitle),
              const SizedBox(height: 8),
              const Text(
                  'Queue your message behind it, or steer the running turn toward it.',
                  style: PT.small),
              const SizedBox(height: 20),
              GradientButton(
                label: 'Queue message',
                onTap: () => Navigator.pop(context, 'queue'),
              ),
              const SizedBox(height: 12),
              TonalButton(
                label: 'Steer turn',
                onTap: () => Navigator.pop(context, 'steer'),
              ),
              const SizedBox(height: 12),
              TonalButton(
                label: 'Dismiss',
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    setState(() => _sending = true);
    final optimistic =
        TranscriptItem(type: 'message', role: 'user', content: text);
    _addOptimistic(optimistic);
    try {
      final result = await widget.api.sendRunMessage(widget.runId, text,
          queue: true, steer: choice == 'steer');
      _queuedByMe = true;
      if (!mounted) return;
      toast(
          context,
          result.steered
              ? 'Steering the running turn…'
              : 'Queued — sends when the turn settles.');
      _poll ??=
          Timer.periodic(const Duration(seconds: 3), (_) => _pollOnce());
      await _pollOnce();
    } on PantheonTurnInFlightException {
      if (mounted) _removeOptimistic(optimistic);
    } catch (e) {
      if (!mounted) return;
      _removeOptimistic(optimistic);
      toastError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Answer a parked `ask_user` question and resume the turn.
  Future<void> _answerInput(String callId) async {
    final answer = _answerCtrl.text.trim();
    if (answer.isEmpty) return;
    _answerCtrl.clear();
    final optimistic =
        TranscriptItem(type: 'message', role: 'user', content: answer);
    _addOptimistic(optimistic);
    _animateToBottom();
    try {
      await widget.api.answerInput(widget.runId, callId, answer);
      _poll ??=
          Timer.periodic(const Duration(seconds: 3), (_) => _pollOnce());
      await _pollOnce();
    } catch (e) {
      if (!mounted) return;
      _removeOptimistic(optimistic);
      toastError(context, e);
    }
  }

  Future<void> _decideApproval(Approval a, bool grant) async {
    try {
      await widget.api.decideApproval(a.id, grant);
      if (!mounted) return;
      toast(context, grant ? 'Granted — resuming.' : 'Denied.');
      await _load();
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  Future<void> _stopTurn() async {
    try {
      await widget.api.cancelRun(widget.runId);
      if (!mounted) return;
      toast(context, 'Stopping…');
      await _pollOnce();
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  Future<void> _setMode(String mode) async {
    if (_run?.mode == mode) return;
    try {
      final effective = await widget.api.setRunMode(widget.runId, mode);
      if (!mounted) return;
      await _load();
      toast(
          context,
          effective == 'plan'
              ? 'Plan mode — Pantheon proposes, you approve.'
              : 'Build mode.');
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  /// Drop the queued message. The optimistic bubble (if any) is
  /// retracted by the [_load] below, which reconciles from the server.
  Future<void> _clearQueue() async {
    try {
      await widget.api.clearQueue(widget.runId);
      _queuedByMe = false;
      if (!mounted) return;
      toast(context, 'Queue cleared.');
      await _load();
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  /// Tap the queued chip to send it now.
  Future<void> _drainQueue() async {
    final text = _run?.queuedMessage;
    if (text == null || text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.api.sendRunMessage(widget.runId, text);
      _queuedByMe = false;
      await widget.api.clearQueue(widget.runId);
      _poll ??=
          Timer.periodic(const Duration(seconds: 3), (_) => _pollOnce());
      await _pollOnce();
    } on PantheonTurnInFlightException {
      if (mounted) toast(context, 'A turn started — still queued.');
    } catch (e) {
      if (mounted) toastError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _openTodosSheet() async {
    await showTodosSheet(context, widget.api, widget.runId);
    if (mounted) await _load();
  }

  // ------------------------------------------------------------------
  // Slash commands
  // ------------------------------------------------------------------

  Future<void> _runSlash(String text) async {
    final rest = text.substring(1);
    final space = rest.indexOf(RegExp(r'\s'));
    final cmd = (space < 0 ? rest : rest.substring(0, space)).toLowerCase();
    final arg = (space < 0 ? '' : rest.substring(space + 1)).trim();
    switch (cmd) {
      case 'new':
        await _slashNew();
        break;
      case 'title':
        await _slashTitle(arg);
        break;
      case 'model':
        await _slashModel();
        break;
      case 'reasoning':
        await _slashReasoning(arg);
        break;
      case 'todos':
        await _openTodosSheet();
        break;
      case 'compress':
        await _slashCompress();
        break;
      case 'export':
        await _slashExport();
        break;
      case 'fork':
        await _slashFork(arg);
        break;
      case 'cancel':
        await _stopTurn();
        break;
      case 'mode':
        await _slashMode(arg);
        break;
      case 'clear':
        await _clearQueue();
        break;
      case 'help':
        await _slashHelp();
        break;
      default:
        if (mounted) toast(context, 'Unknown command /$cmd — try /help.');
    }
  }

  /// New chat sheet (same shape as the Sessions tab), then open it.
  Future<void> _slashNew() async {
    final messageCtrl = TextEditingController();
    final titleCtrl = TextEditingController();
    var busy = false;
    try {
      final created = await showPSheet<PantheonRun>(
        context,
        StatefulBuilder(
          builder: (ctx, setSheet) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                    20, 8, 20, 24 + MediaQuery.of(ctx).viewInsets.bottom),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SheetHandle(),
                    const SizedBox(height: 8),
                    const Text('New chat', style: PT.sectionTitle),
                    const SizedBox(height: 16),
                    TextField(
                      controller: messageCtrl,
                      autofocus: true,
                      minLines: 2,
                      maxLines: 5,
                      style: PT.body,
                      decoration: const InputDecoration(
                        hintText: 'What should Pantheon do?',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: titleCtrl,
                      style: PT.body,
                      decoration: const InputDecoration(
                        hintText: 'Title (optional)',
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: TonalButton(
                              label: 'Cancel',
                              onTap: () => Navigator.pop(ctx)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: GradientButton(
                            label: busy ? 'Starting…' : 'Start',
                            onTap: busy
                                ? null
                                : () async {
                                    final msg = messageCtrl.text.trim();
                                    if (msg.isEmpty) return;
                                    setSheet(() => busy = true);
                                    try {
                                      final run =
                                          await widget.api.createRun(
                                        message: msg,
                                        title: titleCtrl.text.trim().isEmpty
                                            ? null
                                            : titleCtrl.text.trim(),
                                      );
                                      if (ctx.mounted) {
                                        Navigator.pop(ctx, run);
                                      }
                                    } catch (e) {
                                      if (ctx.mounted) {
                                        setSheet(() => busy = false);
                                        toastError(ctx, e);
                                      }
                                    }
                                  },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
      if (created != null && mounted) _openRun(created.id);
    } finally {
      messageCtrl.dispose();
      titleCtrl.dispose();
    }
  }

  Future<void> _slashTitle(String arg) async {
    final title = arg.isNotEmpty
        ? arg
        : await promptText(context,
            title: 'Rename session', initial: _run?.title);
    if (title == null || title.isEmpty || !mounted) return;
    try {
      await widget.api.renameRun(widget.runId, title);
      await _load();
      toast(context, 'Renamed.');
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  /// Switch the default model (same semantics as TUI `/model`: it edits
  /// the global `[model]` section).
  Future<void> _slashModel() async {
    String provider = '';
    String model = '';
    try {
      final doc = await widget.api.getConfig();
      final m = doc.values['model'];
      if (m is Map) {
        provider = m['provider']?.toString() ?? '';
        model = m['model']?.toString() ?? '';
      }
    } catch (_) {}
    if (!mounted) return;
    final pCtrl = TextEditingController(text: provider);
    final mCtrl = TextEditingController(text: model);
    var busy = false;
    try {
      final saved = await showPSheet<bool>(
        context,
        StatefulBuilder(
          builder: (ctx, setSheet) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                    20, 8, 20, 24 + MediaQuery.of(ctx).viewInsets.bottom),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SheetHandle(),
                    const SizedBox(height: 8),
                    const Text('Default model', style: PT.sectionTitle),
                    const SizedBox(height: 4),
                    const Text(
                        'Switches the global [model] default, like /model in the TUI.',
                        style: PT.meta),
                    const SizedBox(height: 16),
                    TextField(
                      controller: pCtrl,
                      style: PT.body,
                      decoration: const InputDecoration(
                        labelText: 'Provider',
                        hintText: 'openai',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: mCtrl,
                      style: PT.body,
                      decoration: const InputDecoration(
                        labelText: 'Model',
                        hintText: 'gpt-4o-mini',
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: TonalButton(
                              label: 'Cancel',
                              onTap: () => Navigator.pop(ctx, false)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: GradientButton(
                            label: busy ? 'Saving…' : 'Save',
                            onTap: busy
                                ? null
                                : () async {
                                    setSheet(() => busy = true);
                                    try {
                                      await widget.api.putConfig({
                                        'model.provider': pCtrl.text.trim(),
                                        'model.model': mCtrl.text.trim(),
                                      });
                                      if (ctx.mounted) {
                                        Navigator.pop(ctx, true);
                                      }
                                    } catch (e) {
                                      if (ctx.mounted) {
                                        setSheet(() => busy = false);
                                        toastError(ctx, e);
                                      }
                                    }
                                  },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
      if (saved == true && mounted) {
        toast(context, 'Default model switched.');
        await _load();
      }
    } finally {
      pCtrl.dispose();
      mCtrl.dispose();
    }
  }

  static const _reasoningLevels = {
    'off',
    'minimal',
    'low',
    'medium',
    'high',
    'xhigh',
    'max'
  };

  /// TUI `/reasoning` persists to `[model]`; "off" clears the key.
  Future<void> _slashReasoning(String arg) async {
    final level = arg.toLowerCase();
    if (!_reasoningLevels.contains(level)) {
      if (mounted) {
        toast(context,
            'Usage: /reasoning off|minimal|low|medium|high|xhigh|max');
      }
      return;
    }
    try {
      await widget.api
          .putConfig({'model.reasoning': level == 'off' ? '' : level});
      if (!mounted) return;
      toast(context, 'Reasoning → $level.');
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  Future<void> _slashCompress() async {
    try {
      final summary = await widget.api.compressRun(widget.runId);
      if (!mounted) return;
      toast(context,
          summary.length > 140 ? '${summary.substring(0, 140)}…' : summary);
      await _load();
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  Future<void> _slashExport() async {
    try {
      final bytes = await widget.api.exportRun(widget.runId);
      if (!mounted) return;
      await showExportSheet(
          context, _run?.displayTitle ?? 'Session', bytes);
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  Future<void> _slashFork(String arg) async {
    int? turn;
    if (arg.isNotEmpty) {
      turn = int.tryParse(arg);
      if (turn == null || turn < 1) {
        if (mounted) toast(context, 'Usage: /fork [turn]');
        return;
      }
    }
    try {
      final forked = await widget.api.forkRun(widget.runId, turn: turn);
      if (!mounted) return;
      toast(context, 'Forked${turn != null ? ' at turn $turn' : ''}.');
      _openRun(forked.id);
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  Future<void> _slashMode(String arg) async {
    final target = arg.toLowerCase();
    if (target == 'plan' || target == 'build') {
      await _setMode(target);
    } else if (arg.isEmpty) {
      await _setMode(_run?.mode == 'plan' ? 'build' : 'plan');
    } else if (mounted) {
      toast(context, 'Usage: /mode [plan|build]');
    }
  }

  Future<void> _slashHelp() {
    return showPSheet<void>(
      context,
      SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SheetHandle(),
              const SizedBox(height: 8),
              const Text('Slash commands', style: PT.sectionTitle),
              const SizedBox(height: 12),
              for (final c in _slashCommands)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 104,
                        child: Text('/${c.name}',
                            style: PT.mono.copyWith(color: P.accent)),
                      ),
                      Expanded(child: Text(c.desc, style: PT.small)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _pickSlash(String cmd) {
    _composer.text = '$cmd ';
    _composer.selection = TextSelection.fromPosition(
        TextPosition(offset: _composer.text.length));
  }

  void _openRun(String id) {
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 280),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, __, ___) =>
            SessionDetailScreen(api: widget.api, runId: id),
        transitionsBuilder: (_, anim, __, child) {
          final slide = Tween<Offset>(
                  begin: const Offset(0.08, 0), end: Offset.zero)
              .animate(
                  CurvedAnimation(parent: anim, curve: Curves.easeOutCubic));
          final fade = Tween<double>(begin: 0, end: 1).animate(
              CurvedAnimation(parent: anim, curve: Curves.easeOut));
          return SlideTransition(
              position: slide,
              child: FadeTransition(opacity: fade, child: child));
        },
      ),
    );
  }

  Color _statusColor(String s) => switch (s) {
        'running' => P.live,
        'awaiting_approval' => P.warn,
        'completed' => P.ok,
        'failed' => P.err,
        _ => P.inkFaint,
      };

  @override
  Widget build(BuildContext context) {
    final title = _run?.displayTitle ?? 'Session';
    final running = _run?.status == 'running';
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.chevron_left_rounded,
              size: 30, color: P.ink, weight: 1.6),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(title),
        actions: [
          if (running)
            IconButton(
              icon: const Icon(Icons.stop_rounded,
                  color: P.err, weight: 1.6),
              tooltip: 'Stop turn',
              onPressed: _stopTurn,
            ),
        ],
      ),
      body: _loading
          ? _skeleton()
          : _error != null
              ? EmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: 'Couldn\'t load session',
                  body: _error!,
                  ctaLabel: 'Retry',
                  onCta: () => _load(initial: true),
                )
              : DefaultTabController(
                  length: 2,
                  child: Column(
                    children: [
                      _header(_run!),
                      TabBar(
                        tabs: const [
                          Tab(text: 'Chat'),
                          Tab(text: 'Timeline')
                        ],
                        labelColor: P.ink,
                        unselectedLabelColor: P.inkMuted,
                        labelStyle: PT.label,
                        indicatorColor: P.accent,
                        indicatorWeight: 2.5,
                        dividerColor: P.divider,
                      ),
                      Expanded(
                        child: TabBarView(
                          children: [
                            _chatTab(),
                            _timeline(_run!),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _header(PantheonRun run) {
    final ctx = run.contextTokens;
    final modelLine = _modelLine ??
        [
          if (run.provider != null && run.provider!.isNotEmpty)
            run.provider!,
          if (run.model != null && run.model!.isNotEmpty) run.model!,
        ].join(' · ');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF2A0A7A), Color(0xFF150548)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(run.displayTitle,
                    style: PT.sectionTitle.copyWith(color: Colors.white)),
              ),
              const SizedBox(width: 8),
              if (run.mode == 'plan')
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: StatusChip(label: 'PLAN', color: P.warn),
                ),
              StatusChip(
                label: run.status.replaceAll('_', ' ').toUpperCase(),
                color: _statusColor(run.status),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${timeAgo(run.createdMs)}${modelLine.isNotEmpty ? ' · $modelLine' : ''}',
            style: PT.small.copyWith(color: const Color(0xFFB9AEE0)),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _modeSegment(run.mode),
              if (_openTodos > 0) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _openTodosSheet,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: P.tonal,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: P.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.checklist_rounded,
                            size: 14, color: P.accent),
                        const SizedBox(width: 6),
                        Text('$_openTodos todos',
                            style: PT.label.copyWith(
                                fontSize: 12, color: P.inkSecondary)),
                      ],
                    ),
                  ),
                ),
              ],
              const Spacer(),
              if (ctx.total > 0)
                Text('${compactNum(ctx.total)} ctx',
                    style: PT.mono.copyWith(
                        fontSize: 11,
                        color: const Color(0xFF8F82C4))),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _stat('${run.turns}', 'turns'),
              _stat('${run.toolCalls}', 'tools'),
              _stat(compactNum(run.totalTokens), 'tokens'),
              _stat(money(run.costUsd), 'cost'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String value, String label) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: PT.label.copyWith(color: Colors.white, fontSize: 16)),
          Text(label, style: PT.faint.copyWith(color: const Color(0xFF8F82C4))),
        ],
      ),
    );
  }

  Widget _modeSegment(String mode) {
    return Container(
      decoration: BoxDecoration(
        color: P.tonal,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: P.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _modePill('Plan', mode == 'plan', () => _setMode('plan')),
          _modePill('Build', mode != 'plan', () => _setMode('build')),
        ],
      ),
    );
  }

  Widget _modePill(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: selected ? P.accentSoft : Colors.transparent,
          border: Border.all(
              color: selected ? P.accent : Colors.transparent, width: 1),
        ),
        child: Text(label,
            style: PT.label.copyWith(
                fontSize: 12,
                color: selected ? P.ink : P.inkMuted)),
      ),
    );
  }

  Widget _chatTab() {
    final run = _run;
    return Column(
      children: [
        Expanded(child: _messageList()),
        if (run != null && run.pendingInput.isNotEmpty)
          _clarifyCard(run.pendingInput.first),
        if (run != null && run.status == 'awaiting_approval')
          _approvalBanner(),
        if (run != null &&
            run.queuedMessage != null &&
            run.queuedMessage!.isNotEmpty)
          _queuedChip(run.queuedMessage!),
        _SlashSuggestions(controller: _composer, onPick: _pickSlash),
        _composerBar(),
      ],
    );
  }

  /// The TUI clarify card: question, tappable option chips, answer field.
  Widget _clarifyCard(PendingInput pi) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: P.surface,
        borderRadius: BorderRadius.circular(P.r16),
        border: Border.all(color: P.warn.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.help_outline_rounded,
                  size: 18, color: P.warn),
              const SizedBox(width: 8),
              Text('Pantheon is asking',
                  style: PT.label.copyWith(color: P.warn)),
            ],
          ),
          const SizedBox(height: 8),
          Text(pi.question, style: PT.body.copyWith(fontSize: 14)),
          if (pi.options.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final o in pi.options)
                  PillChip(
                    label: o,
                    selected: false,
                    onTap: () => setState(() => _answerCtrl.text = o),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _answerCtrl,
                  minLines: 1,
                  maxLines: 3,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _answerInput(pi.callId),
                  style: PT.body.copyWith(fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: 'Your answer…',
                    contentPadding: EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _answerInput(pi.callId),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(
                    gradient: P.gradient,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.arrow_upward_rounded,
                      color: Colors.white, size: 22),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Inline grant/deny for approvals parked on this run.
  Widget _approvalBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: P.surface,
        borderRadius: BorderRadius.circular(P.r16),
        border: Border.all(color: P.warn.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.gpp_maybe_rounded, size: 18, color: P.warn),
              const SizedBox(width: 8),
              Text('Needs your approval',
                  style: PT.label.copyWith(color: P.warn)),
            ],
          ),
          const SizedBox(height: 10),
          if (_runApprovals.isEmpty)
            const Text('Waiting on an approval decision…',
                style: PT.small)
          else
            for (final a in _runApprovals) ...[
              _approvalRow(a),
              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }

  Widget _approvalRow(Approval a) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(a.tool ?? 'Approval',
                  style: PT.rowTitle.copyWith(fontSize: 14)),
              const SizedBox(height: 2),
              Text(a.id,
                  style: PT.monoSm,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        const SizedBox(width: 8),
        PillButton(
            label: 'Deny',
            color: P.err,
            onTap: () => _decideApproval(a, false)),
        const SizedBox(width: 8),
        PillButton(
            label: 'Grant',
            color: P.ok,
            onTap: () => _decideApproval(a, true)),
      ],
    );
  }

  /// The queued follow-up: tap to send now, × to drop.
  Widget _queuedChip(String text) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: P.accentSoft,
        borderRadius: BorderRadius.circular(999),
        border:
            Border.all(color: P.accent.withValues(alpha: 0.4), width: 1),
      ),
      child: Row(
        children: [
          const Icon(Icons.schedule_rounded, size: 16, color: P.accent),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: _drainQueue,
              child: Text('Queued: $text',
                  style: PT.small,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
          ),
          GestureDetector(
            onTap: _clearQueue,
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close_rounded,
                  size: 18, color: P.inkMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _messageList() {
    if (_messages.isEmpty) {
      return const EmptyState(
        icon: Icons.chat_bubble_outline_rounded,
        title: 'No messages yet',
        body: 'Say something below to start the conversation.',
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      itemCount: _messages.length,
      itemBuilder: (context, i) =>
          StaggerItem(index: i, child: _bubble(_messages[i])),
    );
  }

  Widget _composerBar() {
    return Container(
      decoration: const BoxDecoration(
        color: P.tabBar,
        border: Border(top: BorderSide(color: P.border, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: _composerRow(),
        ),
      ),
    );
  }

  Widget _composerRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: _composer,
            enabled: !_sending,
            minLines: 1,
            maxLines: 5,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _send(),
            style: PT.body.copyWith(fontSize: 14),
            decoration: const InputDecoration(
              hintText: 'Message Pantheon…  ( / for commands)',
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _send,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: _sending ? 0.5 : 1,
            child: Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                gradient: P.gradient,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: _sending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: Colors.white),
                    )
                  : const Icon(Icons.arrow_upward_rounded,
                      color: Colors.white, size: 22),
            ),
          ),
        ),
      ],
    );
  }

  Widget _bubble(TranscriptItem t) {
    if (t.type == 'reasoning') {
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: P.surface,
          borderRadius: BorderRadius.circular(P.r12),
          border: Border.all(color: P.border),
        ),
        child: Text(t.content,
            style: PT.small
                .copyWith(fontStyle: FontStyle.italic, color: P.inkMuted)),
      );
    }
    final isUser = t.role == 'user';
    final isTool = t.role == 'tool';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.85),
        decoration: BoxDecoration(
          gradient: isUser ? P.gradient : null,
          color: isUser
              ? null
              : isTool
                  ? P.tonal
                  : P.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(P.r18),
            topRight: const Radius.circular(P.r18),
            bottomLeft: Radius.circular(isUser ? P.r18 : P.r4),
            bottomRight: Radius.circular(isUser ? P.r4 : P.r18),
          ),
          border: isUser ? null : Border.all(color: P.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isUser)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text((t.role ?? 'assistant').toUpperCase(),
                    style: PT.monoEyebrow
                        .copyWith(color: isTool ? P.info : P.accent)),
              ),
            SelectableText(t.content,
                style: PT.body.copyWith(
                    fontSize: 14, color: isUser ? Colors.white : P.ink)),
          ],
        ),
      ),
    );
  }

  Widget _timeline(PantheonRun run) {
    if (run.timeline.isEmpty) {
      return const EmptyState(
        icon: Icons.timeline_rounded,
        title: 'No timeline events',
        body: 'Run events will stream in here.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 24),
      itemCount: run.timeline.length,
      itemBuilder: (context, i) {
        final e = run.timeline[i];
        final last = i == run.timeline.length - 1;
        return StaggerItem(
          index: i,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _kindColor(e.kind),
                      boxShadow: [
                        BoxShadow(
                          color: _kindColor(e.kind).withValues(alpha: 0.5),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                  if (!last) Container(width: 2, height: 30, color: P.border),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.kind.replaceAll('_', ' '),
                          style: PT.label.copyWith(fontSize: 13)),
                      if (e.detail != null && e.detail!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(e.detail!,
                              style: PT.meta,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(timeAgo(e.tsMs), style: PT.faint),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Color _kindColor(String kind) {
    if (kind.contains('failed') || kind.contains('denied')) return P.err;
    if (kind.contains('approval')) return P.warn;
    if (kind.contains('completed') || kind.contains('granted')) return P.ok;
    return P.accent;
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  void _animateToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  Widget _skeleton() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        Shimmer(width: double.infinity, height: 120, radius: 16),
        SizedBox(height: 12),
        Shimmer(width: double.infinity, height: 80, radius: 14),
        SizedBox(height: 10),
        Shimmer(width: 240, height: 80, radius: 14),
      ],
    );
  }
}

/// One slash command: name + one-line description.
class _SlashCommand {
  final String name;
  final String desc;
  const _SlashCommand(this.name, this.desc);
}

const _slashCommands = [
  _SlashCommand('new', 'start a new chat'),
  _SlashCommand('title', 'rename this session: /title <text>'),
  _SlashCommand('model', 'switch the default model'),
  _SlashCommand(
      'reasoning', 'reasoning effort: off|minimal|low|medium|high|xhigh|max'),
  _SlashCommand('todos', 'session todo list'),
  _SlashCommand('compress', 'compress context now'),
  _SlashCommand('export', 'copy transcript as markdown'),
  _SlashCommand('fork', 'fork session at a turn: /fork [turn]'),
  _SlashCommand('cancel', 'stop the running turn'),
  _SlashCommand('mode', 'switch plan/build: /mode [plan|build]'),
  _SlashCommand('clear', 'clear the queued message'),
  _SlashCommand('help', 'list slash commands'),
];

/// Suggestion popup above the composer while the first word starts with `/`.
/// Own listener, so typing doesn't rebuild the whole screen.
class _SlashSuggestions extends StatefulWidget {
  final TextEditingController controller;
  final ValueChanged<String> onPick;

  const _SlashSuggestions({required this.controller, required this.onPick});

  @override
  State<_SlashSuggestions> createState() => _SlashSuggestionsState();
}

class _SlashSuggestionsState extends State<_SlashSuggestions> {
  bool _show = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
    _onChange();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    final text = widget.controller.text;
    final show = text.startsWith('/') &&
        !text.contains(' ') &&
        !text.contains('\n');
    final query = show ? text.substring(1).toLowerCase() : '';
    if ((show != _show || query != _query) && mounted) {
      setState(() {
        _show = show;
        _query = query;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return const SizedBox.shrink();
    final matches = _slashCommands
        .where((c) => c.name.startsWith(_query))
        .toList();
    if (matches.isEmpty) return const SizedBox.shrink();
    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      decoration: BoxDecoration(
        color: P.surface,
        borderRadius: BorderRadius.circular(P.r12),
        border: Border.all(color: P.borderStrong),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: matches.length,
        itemBuilder: (_, i) {
          final c = matches[i];
          return InkWell(
            onTap: () => widget.onPick('/${c.name}'),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Row(
                children: [
                  SizedBox(
                    width: 104,
                    child: Text('/${c.name}',
                        style: PT.mono.copyWith(color: P.accent)),
                  ),
                  Expanded(
                    child: Text(c.desc,
                        style: PT.small,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
