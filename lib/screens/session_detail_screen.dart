import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../models/models.dart';
import '../services/app_preferences.dart';
import '../services/pantheon_api.dart';
import '../theme.dart';
import '../widgets/agent_avatar.dart';
import '../widgets/buttons.dart';
import '../widgets/chips.dart';
import '../widgets/export_sheet.dart';
import '../widgets/forms.dart';
import '../widgets/message_content.dart';
import '../widgets/new_chat_sheet.dart';
import '../widgets/states.dart';
import '../widgets/todos_sheet.dart';
import '../widgets/voice_note_pill.dart';
import 'voice_screen.dart';

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

  /// Optional badge notifier for the Approvals tab. Refreshed after
  /// inline grant/deny decisions made on this screen.
  final ValueNotifier<int>? pendingApprovals;

  const SessionDetailScreen(
      {super.key,
      required this.api,
      required this.runId,
      this.pendingApprovals});

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
  final _composerFocus = FocusNode();
  final _answerCtrl = TextEditingController();
  final _scroll = ScrollController();
  Timer? _poll;
  bool _sending = false;
  bool _atBottom = true;

  /// True while a manual `/compress` round-trip is in flight. Drives the
  /// "Compressing context…" status row above the composer and guards
  /// against double-taps (compression is a slow LLM call).
  bool _compressing = false;

  /// Guard against double-tapping the clarify-card send button: the
  /// answer POST must fire at most once per question.
  bool _answering = false;

  /// Approvals parked on this run (inline banner).
  List<Approval> _runApprovals = [];

  /// Open (non-completed) todo count for the header chip.
  int _openTodos = 0;

  /// `provider · model` from the `[model]` config section.
  String? _modelLine;

  /// How many of the run's queued messages were parked from this screen.
  /// The poller auto-drains them oldest-first as turns settle; steer
  /// resets this to 1 because it wipes the server queue and parks just
  /// the steered message.
  int _queuedByMe = 0;

  /// Whether the queue section lists its messages expanded.
  bool _queueExpanded = false;

  /// Retry of a failed turn is in flight.
  bool _retrying = false;

  /// Attachments staged on the composer: picked locally, uploaded to
  /// `POST /api/uploads`, then sent with the message as attachment ids.
  final List<_PendingAttachment> _attachments = [];

  /// Memoized thumbnail futures for sent image attachments, keyed by
  /// upload id — `GET /api/uploads/:id` bytes cached per session.
  final Map<String, Future<Uint8List>> _thumbFutures = {};

  /// Voice-note recording state. The composer mic starts a recording
  /// (the pill); the AppBar mic still opens the live voice screen.
  bool _recordingVoiceNote = false;

  /// True while a finished voice note is being transcribed.
  bool _transcribing = false;

  /// Recorder for the in-flight voice note; the pill drives it and the
  /// parent disposes it once the pill reports back.
  AudioRecorder? _voiceRecorder;

  /// Timeline rows the user expanded, by item seq.
  final Set<int> _expandedTl = {};

  static bool _isLive(String status) =>
      status == 'running' || status == 'awaiting_approval';

  /// The `[attachments]` block the server appends to a user message when
  /// files were attached — stripped before rendering the bubble so the
  /// raw file list never shows in chat. The parsed form renders as the
  /// attachment grid instead.
  static final _attachmentBlock = RegExp(r'\n*\[attachments\][\s\S]*$');

  /// One line of the block: `- name (mime, size[, id: upl_xxx]): /path`.
  /// The `id:` part is new; old lines without it still parse (id null).
  static final _attachmentLine = RegExp(
      r'^- (.*) \(([^,()]*), ([^,()]*)(?:, id: ([^()]*))?\): ');

  /// Parse the `[attachments]` block into (name, mime, id) records.
  /// Never throws — unparseable lines are skipped.
  static List<_SentAttachment> _parseSentAttachments(String content) {
    final out = <_SentAttachment>[];
    for (final raw in content.split('\n')) {
      final line = raw.trimRight();
      if (!line.startsWith('- ')) continue;
      final m = _attachmentLine.firstMatch(line);
      if (m == null) continue;
      final name = m.group(1)!.trim();
      final mime = m.group(2)!.trim();
      final id = m.group(4)?.trim();
      if (name.isEmpty) continue;
      out.add(_SentAttachment(
        name: name,
        mime: mime.isEmpty ? 'application/octet-stream' : mime,
        id: (id == null || id.isEmpty) ? null : id,
      ));
    }
    return out;
  }

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
    // Best-effort: abandon any in-flight voice-note recording. The pill
    // is gone with the widget tree, so cancel here instead of the
    // normal discard path (no setState in dispose).
    final vr = _voiceRecorder;
    _voiceRecorder = null;
    if (vr != null) {
      () async {
        try {
          await vr.cancel();
        } catch (_) {}
        try {
          await vr.dispose();
        } catch (_) {}
      }();
    }
    _composer.dispose();
    _composerFocus.dispose();
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

  /// Poll cadence while a turn is live.
  static const _pollInterval = Duration(seconds: 3);

  /// Start the periodic poller if it isn't already running.
  void _ensurePolling() {
    _poll ??= Timer.periodic(_pollInterval, (_) => _pollOnce());
  }

  void _syncPolling(String status) {
    final live = _isLive(status);
    if (live) {
      _ensurePolling();
    } else {
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
      // Turn settled: haptic + auto-drain the oldest message this
      // screen queued, if any are still waiting server-side.
      if (wasLive && !_isLive(run.status)) {
        _haptic(HapticFeedback.lightImpact);
      }
      if (wasLive && !_isLive(run.status) && _queuedByMe > 0) {
        final queue = run.queuedMessages;
        if (queue.isEmpty) {
          _queuedByMe = 0;
        } else {
          // Attempt the drain; on failure _drainQueueText keeps the
          // poller alive (turn-in-flight) so the next settle retries.
          if (await _drainQueueText(queue.first)) _queuedByMe--;
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
  ///
  /// Admission is counted per key, not just keyed: two identical rapid
  /// messages share one [_msgKey], so each admitted occurrence retracts
  /// exactly one pending bubble instead of all of them at once.
  bool _syncMessages(List<TranscriptItem> fresh) {
    final admitted = <String, int>{};
    for (final t in fresh) {
      final k = _msgKey(t);
      admitted[k] = (admitted[k] ?? 0) + 1;
    }
    _pending.removeWhere((t) {
      final k = _msgKey(t);
      final n = admitted[k] ?? 0;
      if (n > 0) {
        admitted[k] = n - 1;
        return true;
      }
      return false;
    });
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

  /// Send the oldest queued message as a normal turn now that the run
  /// settled. Returns true when the turn started. The server pops the
  /// head of its FIFO queue on the idle send, so the rest stay queued —
  /// never clear the whole queue here.
  Future<bool> _drainQueueText(String text) async {
    try {
      await widget.api.sendRunMessage(widget.runId, text);
      _ensurePolling();
      await _pollOnce();
      return true;
    } on PantheonTurnInFlightException {
      // A new turn started before we drained; keep polling so the next
      // settle retries.
      _ensurePolling();
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _send() async {
    final raw = _composer.text.trim();
    final ids = _attachments
        .where((a) => a.record != null)
        .map((a) => a.record!.id)
        .toList();
    if ((raw.isEmpty && ids.isEmpty) || _sending) return;
    if (_attachments.any((a) => a.uploading)) {
      toast(context, 'Waiting for uploads to finish…');
      return;
    }
    _haptic(HapticFeedback.mediumImpact);
    // `//` escapes the slash-command prefix: `//deploy` sends a literal
    // `/deploy` as chat text instead of running a command.
    final escaped = raw.startsWith('//');
    if (raw.startsWith('/') && !escaped) {
      _composer.clear();
      await _runSlash(raw);
      return;
    }
    final text = escaped ? raw.substring(1) : raw;
    final messageText = text.isEmpty
        ? '(shared ${ids.length} attachment${ids.length == 1 ? '' : 's'})'
        : text;
    final run = _run;
    if (run == null || !_canChat(run.status)) return;
    if (_isLive(run.status)) {
      // Smart send/stop: a turn is already in flight, so the composer
      // button is a stop button — offer stop / interrupt / queue / steer.
      await _stopSheet();
      return;
    }
    setState(() => _sending = true);
    // The composer keeps its draft until the send succeeds: on failure
    // the user gets their text back instead of losing it.
    final optimistic = TranscriptItem(
        type: 'message',
        role: 'user',
        content: messageText,
        tsMs: DateTime.now().millisecondsSinceEpoch);
    _addOptimistic(optimistic);
    _animateToBottom();
    try {
      final result = await widget.api.sendRunMessage(
        run.id,
        messageText,
        attachments: ids,
      );
      // Success: the draft and the staged attachments are on their way.
      if (mounted) {
        setState(() {
          _composer.clear();
          _attachments.clear();
        });
      }
      if (result.queued || result.steered) {
        _queuedByMe++;
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
      _ensurePolling();
      await _pollOnce();
    } on PantheonTurnInFlightException {
      // Lost the idle→busy race between the check above and the send:
      // the run really is busy, so offer the same stop sheet.
      if (!mounted) return;
      _removeOptimistic(optimistic);
      await _stopSheet();
    } catch (e) {
      if (!mounted) return;
      _removeOptimistic(optimistic);
      _haptic(HapticFeedback.heavyImpact);
      toastError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Smart send/stop: the composer button is a stop button while a turn
  /// is in flight. Offers hard stop, cooperative interrupt, and
  /// queue/steer of the composer's draft. Queue/steer are only tappable
  /// when the composer holds a draft and the run is actually running
  /// (a parked run 409s message sends until its approval is decided).
  Future<void> _stopSheet() async {
    final raw = _composer.text.trim();
    final ids = _attachments
        .where((a) => a.record != null)
        .map((a) => a.record!.id)
        .toList();
    final hasDraft = raw.isNotEmpty || ids.isNotEmpty;
    final canQueue = hasDraft && _run?.status == 'running';
    // Same draft normalization as [_send]: `//` unescapes, and an
    // attachments-only draft gets a placeholder line.
    final escaped = raw.startsWith('//');
    final text = escaped ? raw.substring(1) : raw;
    final messageText = text.isEmpty
        ? '(shared ${ids.length} attachment${ids.length == 1 ? '' : 's'})'
        : text;
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
              Text('Turn in flight', style: PT.sectionTitle),
              const SizedBox(height: 8),
              Text(
                'Stop the model, interrupt it, or park this message behind it.',
                style: PT.small),
              const SizedBox(height: 20),
              _DangerSheetButton(
                label: 'Stop the model',
                onTap: () => Navigator.pop(context, 'kill'),
              ),
              const SizedBox(height: 12),
              TonalButton(
                label: 'Interrupt',
                onTap: () => Navigator.pop(context, 'interrupt'),
              ),
              const SizedBox(height: 12),
              Opacity(
                opacity: canQueue ? 1 : 0.4,
                child: TonalButton(
                  label: 'Queue the message',
                  onTap: canQueue
                      ? () => Navigator.pop(context, 'queue')
                      : null,
                ),
              ),
              const SizedBox(height: 12),
              Opacity(
                opacity: canQueue ? 1 : 0.4,
                child: TonalButton(
                  label: 'Steer the message',
                  onTap: canQueue
                      ? () => Navigator.pop(context, 'steer')
                      : null,
                ),
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
    switch (choice) {
      case 'kill':
        await _hardStopTurn();
      case 'interrupt':
        await _stopTurn();
      case 'queue':
      case 'steer':
        await _queueOrSteer(choice == 'steer', messageText, ids);
    }
  }

  /// Hard stop: force-terminates the in-flight turn process. Unlike
  /// [_stopTurn] (cooperative), this does not wait for a checkpoint.
  /// The button state comes back from the server afterwards — never
  /// assumed.
  Future<void> _hardStopTurn() async {
    _haptic(HapticFeedback.heavyImpact);
    try {
      await widget.api.killRun(widget.runId);
    } catch (e) {
      if (!mounted) return;
      toastError(context, e);
      return;
    }
    if (!mounted) return;
    toast(context, 'Stopped.');
    _ensurePolling();
    await _pollOnce();
  }

  /// Queue or steer the composer's draft behind/into the running turn.
  Future<void> _queueOrSteer(
      bool steer, String text, List<String> attachments) async {
    if (!mounted) return;
    setState(() => _sending = true);
    final optimistic =
        TranscriptItem(type: 'message', role: 'user', content: text);
    _addOptimistic(optimistic);
    try {
      final result = await widget.api.sendRunMessage(widget.runId, text,
          queue: true, steer: steer, attachments: attachments);
      // Steer wipes the server queue and parks just this message; a
      // plain queue appends behind what's already waiting.
      _queuedByMe = result.steered ? 1 : _queuedByMe + 1;
      // The draft and staged attachments are now queued/steered with the
      // message: clear them so a later send can't attach them twice.
      if (mounted) {
        setState(() {
          _composer.clear();
          _attachments.clear();
        });
      }
      if (!mounted) return;
      toast(
          context,
          result.steered
              ? 'Steering the running turn…'
              : 'Queued — sends when the turn settles.');
      _ensurePolling();
      await _pollOnce();
    } on PantheonTurnInFlightException {
      if (mounted) _removeOptimistic(optimistic);
    } catch (e) {
      if (!mounted) return;
      _removeOptimistic(optimistic);
      _haptic(HapticFeedback.heavyImpact);
      toastError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Answer a parked `ask_user` question and resume the turn.
  Future<void> _answerInput(String callId) async {
    if (_answering) return;
    final answer = _answerCtrl.text.trim();
    if (answer.isEmpty) return;
    _answering = true;
    _answerCtrl.clear();
    final optimistic =
        TranscriptItem(type: 'message', role: 'user', content: answer);
    _addOptimistic(optimistic);
    _animateToBottom();
    try {
      await widget.api.answerInput(widget.runId, callId, answer);
      _ensurePolling();
      await _pollOnce();
    } catch (e) {
      if (!mounted) return;
      _removeOptimistic(optimistic);
      toastError(context, e);
    } finally {
      _answering = false;
    }
  }

  Future<void> _decideApproval(Approval a, bool grant) async {
    try {
      await widget.api.decideApproval(a.id, grant);
      if (!mounted) return;
      toast(context, grant ? 'Granted — resuming.' : 'Denied.');
      await _refreshApprovalsBadge();
      await _load();
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  /// Keep the Approvals tab badge honest after an inline decision: the
  /// badge only refreshes on Home/Approvals screen loads otherwise.
  Future<void> _refreshApprovalsBadge() async {
    final notifier = widget.pendingApprovals;
    if (notifier == null) return;
    try {
      final all = await widget.api.approvals();
      if (!mounted) return;
      notifier.value = all.length;
    } catch (_) {}
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

  /// Drop every queued message. The optimistic bubbles (if any) are
  /// retracted by the [_load] below, which reconciles from the server.
  Future<void> _clearQueue() async {
    final ok = await confirmAction(
      context,
      title: 'Clear queued messages?',
      body: 'Every message waiting behind the current turn will be dropped.',
      confirmLabel: 'Clear queue',
      destructive: true,
    );
    if (!ok) return;
    try {
      await widget.api.clearQueue(widget.runId);
      _queuedByMe = 0;
      if (!mounted) return;
      toast(context, 'Queue cleared.');
      await _load();
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  /// Retry a failed turn from the timeline header. The server replays the
  /// last user message, so the client never resends text.
  Future<void> _retryRun() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    try {
      await widget.api.retryRun(widget.runId);
      if (!mounted) return;
      toast(context, 'Retrying turn…');
      // Back to Chat so the new turn is visible; the poll loop picks it up.
      DefaultTabController.of(context)?.animateTo(0);
      _ensurePolling();
      await _load();
    } on PantheonTurnInFlightException {
      if (mounted) toast(context, 'A turn is already running.');
    } on PantheonRetryParkedException {
      if (mounted) {
        toast(context, 'Parked on approval — grant or deny it first.');
      }
    } catch (e) {
      if (mounted) toastError(context, e);
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  /// Tap the queue header to send the oldest queued message now. The
  /// server pops the head of its FIFO queue on the idle send, so the
  /// rest stay queued — never clear the whole queue here.
  Future<void> _drainQueue() async {
    final queue = _run?.queuedMessages ?? [];
    if (queue.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.api.sendRunMessage(widget.runId, queue.first);
      if (_queuedByMe > 0) _queuedByMe--;
      _ensurePolling();
      await _pollOnce();
    } on PantheonTurnInFlightException {
      if (mounted) toast(context, 'A turn started — still queued.');
    } catch (e) {
      if (mounted) toastError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Edit one queued message in place. The run is reloaded from the
  /// server afterwards so index shifts can never desync the list.
  Future<void> _editQueueItem(int index, String current) async {
    final ctrl = TextEditingController(text: current);
    var busy = false;
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
                  Text('Edit queued message', style: PT.sectionTitle),
                  const SizedBox(height: 4),
                  Text('It stays queued until the turn settles.',
                      style: PT.meta),
                  const SizedBox(height: 16),
                  TextField(
                    controller: ctrl,
                    style: PT.body,
                    maxLines: 5,
                    minLines: 2,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Message text',
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
                                  final text = ctrl.text.trim();
                                  if (text.isEmpty) {
                                    toast(ctx, 'Message can\'t be empty.');
                                    return;
                                  }
                                  setSheet(() => busy = true);
                                  try {
                                    await widget.api.editQueueItem(
                                        widget.runId, index, text);
                                    if (ctx.mounted) Navigator.pop(ctx, true);
                                  } catch (e) {
                                    setSheet(() => busy = false);
                                    if (ctx.mounted) toastError(ctx, e);
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
    ctrl.dispose();
    if (saved == true && mounted) {
      toast(context, 'Queued message updated.');
      await _load();
    }
  }

  /// Delete one queued message after a confirm. The run is reloaded
  /// from the server afterwards so index shifts stay correct.
  Future<void> _deleteQueueItem(int index) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: P.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete queued message?', style: PT.cardTitle),
        content: Text('This can\'t be undone.', style: PT.body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: PT.label.copyWith(color: P.inkMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: PT.label.copyWith(color: P.err)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.deleteQueueItem(widget.runId, index);
      if (!mounted) return;
      toast(context, 'Queued message deleted.');
      await _load();
    } catch (e) {
      if (mounted) toastError(context, e);
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

  /// `/new`: open the shared new-chat sheet, which pushes the created
  /// session's detail view itself.
  Future<void> _slashNew() async {
    await showNewChatSheet(context, widget.api);
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
                     Text('Default model', style: PT.sectionTitle),
                    const SizedBox(height: 4),
                     Text(
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
    if (_compressing) return;
    setState(() => _compressing = true);
    try {
      final summary = await widget.api.compressRun(widget.runId);
      if (!mounted) return;
      toast(context,
          summary.length > 140 ? '${summary.substring(0, 140)}…' : summary);
      await _load();
    } catch (e) {
      if (mounted) toastError(context, e);
    } finally {
      if (mounted) setState(() => _compressing = false);
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
               Text('Slash commands', style: PT.sectionTitle),
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
              const SizedBox(height: 2),
              Text('Tip: start with // to send a literal leading slash.',
                  style: PT.small.copyWith(color: P.inkMuted)),
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
      buildDetailRoute(SessionDetailScreen(
          api: widget.api,
          runId: id,
          pendingApprovals: widget.pendingApprovals)),
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
          icon:  Icon(Icons.chevron_left_rounded,
              size: 30, color: P.ink, weight: 1.6),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(title),
        actions: [
          IconButton(
            icon: Icon(Icons.mic_rounded, color: P.ink, weight: 1.6),
            tooltip: 'Live voice',
            onPressed: _openVoice,
          ),
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
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [P.accent, P.accentDeep],
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
            style: PT.small.copyWith(
                color: Colors.white.withValues(alpha: 0.75)),
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
                         Icon(Icons.checklist_rounded,
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
                        color: Colors.white.withValues(alpha: 0.6))),
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
          Text(label,
              style: PT.faint.copyWith(
                  color: Colors.white.withValues(alpha: 0.6))),
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
    final chatBg = AppPreferences.instance.chatBg.value;
    final bg = switch (chatBg) {
      'tinted' => P.accentSoft,
      'dim' => P.tonal,
      _ => null,
    };
    return Container(
      color: bg,
      child: Column(
        children: [
          Expanded(child: _messageList()),
          if (run != null && run.pendingInput.isNotEmpty)
            _clarifyCard(run.pendingInput.first),
          if (run != null && run.status == 'awaiting_approval')
            _approvalBanner(),
          if (run != null && run.queuedMessages.isNotEmpty)
            _queueSection(run.queuedMessages),
          _SlashSuggestions(controller: _composer, onPick: _pickSlash),
          _composerBar(),
        ],
      ),
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
              Icon(Icons.gpp_maybe_rounded, size: 18, color: P.warn),
              const SizedBox(width: 8),
              Text('Needs your approval',
                  style: PT.label.copyWith(color: P.warn)),
            ],
          ),
          const SizedBox(height: 10),
          if (_runApprovals.isEmpty)
             Text('Waiting on an approval decision…',
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

  /// The queued follow-ups as a FIFO section, oldest first. Collapsed it
  /// shows the count; expanded it lists each message. Tap the label to
  /// send the oldest now; Clear drops the whole server queue.
  Widget _queueSection(List<String> queue) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: P.accentSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: P.accent.withValues(alpha: 0.4), width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.schedule_rounded, size: 16, color: P.accent),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: _drainQueue,
                  child: Text(
                    '${queue.length} queued',
                    style: PT.small,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              GestureDetector(
                onTap: _clearQueue,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Text('Clear',
                      style: PT.small.copyWith(color: P.accent)),
                ),
              ),
              GestureDetector(
                onTap: () =>
                    setState(() => _queueExpanded = !_queueExpanded),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    _queueExpanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 18,
                    color: P.inkMuted,
                  ),
                ),
              ),
            ],
          ),
          if (_queueExpanded) ...[
            const SizedBox(height: 4),
            for (var i = 0; i < queue.length; i++)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('${i + 1}.',
                          style: PT.meta.copyWith(color: P.inkFaint)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(queue[i],
                            style: PT.small.copyWith(color: P.inkMuted),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _editQueueItem(i, queue[i]),
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(Icons.edit_outlined,
                            size: 16, color: P.inkMuted),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _deleteQueueItem(i),
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(Icons.delete_outline_rounded,
                            size: 16, color: P.inkMuted),
                      ),
                    ),
                  ],
                ),
              ),
          ],
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
    // Interleave day dividers when enabled (only items carrying a real
    // timestamp can trigger one).
    final prefs = AppPreferences.instance;
    final dividers = prefs.dateDividers.value;
    final rows = <Widget>[];
    DateTime? lastDay;
    for (var i = 0; i < _messages.length; i++) {
      final t = _messages[i];
      if (dividers && t.tsMs != null) {
        final d = DateTime.fromMillisecondsSinceEpoch(t.tsMs!);
        final day = DateTime(d.year, d.month, d.day);
        if (lastDay == null || day != lastDay) {
          rows.add(_dateDivider(day));
          lastDay = day;
        }
      }
      rows.add(StaggerItem(index: i, child: _bubble(t)));
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      itemCount: rows.length,
      itemBuilder: (context, i) => rows[i],
    );
  }

  Widget _composerBar() {
    return Container(
      decoration: BoxDecoration(
        color: P.tabBar,
        border: Border(top: BorderSide(color: P.border, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_compressing) ...[
                _compressingRow(),
                const SizedBox(height: 8),
              ],
              if (_attachments.isNotEmpty) ...[
                _attachmentChips(),
                const SizedBox(height: 8),
              ],
              _transcribing
                  ? _transcribingRow()
                  : _recordingVoiceNote
                      ? _voiceNotePill()
                      : _composerRow(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _composerRow() {
    final returnSends = AppPreferences.instance.returnSends.value;
    final reduceMotion = AppPreferences.instance.reduceMotion.value;
    // Smart send/stop: while a turn is in flight (and we're not mid-send
    // ourselves) the button is a stop button in the Nyx danger wash.
    final stopLive = !_sending && _isLive(_run?.status ?? '');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _composerIconButton(
            Icons.add_rounded, 'Add to chat', _addSheet),
        const SizedBox(width: 4),
        Expanded(
          child: TextField(
            controller: _composer,
            focusNode: _composerFocus,
            enabled: !_sending,
            minLines: 1,
            maxLines: 5,
            textInputAction: returnSends
                ? TextInputAction.send
                : TextInputAction.newline,
            onSubmitted: returnSends ? (_) => _send() : null,
            style: PT.body.copyWith(fontSize: 14),
            decoration: const InputDecoration(
              hintText: 'Message Pantheon…  ( / for commands)',
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ),
        const SizedBox(width: 4),
        _composerIconButton(
            Icons.mic_rounded, 'Record voice note', _startVoiceNote),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: stopLive ? _stopSheet : _send,
          child: AnimatedOpacity(
            duration: Duration(
                milliseconds: reduceMotion ? 0 : 150),
            opacity: _sending ? 0.5 : 1,
            child: Container(
              width: 48,
              height: 48,
              decoration: stopLive
                  ? BoxDecoration(
                      color: P.err.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: P.err.withValues(alpha: 0.5), width: 1.5),
                    )
                  : const BoxDecoration(
                      gradient: P.gradient,
                      shape: BoxShape.circle,
                    ),
              alignment: Alignment.center,
              child: _sending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: _SendGlyph(),
                    )
                  : stopLive
                      ? const Icon(Icons.stop_rounded,
                          color: P.err, size: 22)
                      : const Icon(Icons.arrow_upward_rounded,
                          color: Colors.white, size: 22),
            ),
          ),
        ),
      ],
    );
  }

  /// Round tonal icon button flanking the composer field (`+`, mic).
  Widget _composerIconButton(
      IconData icon, String tooltip, VoidCallback onTap) {
    return GestureDetector(
      onTap: () {
        _haptic(HapticFeedback.lightImpact);
        onTap();
      },
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: P.tonal,
        ),
        alignment: Alignment.center,
        child: Icon(icon,
            size: 22, color: P.inkSecondary, weight: 1.6,
            semanticLabel: tooltip),
      ),
    );
  }

  void _openVoice() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VoiceScreen(api: widget.api),
      ),
    );
  }

  // ------------------------------------------------------ voice notes --

  /// Composer mic: start a voice-note recording. Permission is checked
  /// up front (the `record` plugin requests it); the pill itself starts
  /// the recorder once it mounts.
  Future<void> _startVoiceNote() async {
    if (_recordingVoiceNote || _transcribing || _sending) return;
    final recorder = AudioRecorder();
    if (!await recorder.hasPermission()) {
      await recorder.dispose();
      if (!mounted) return;
      await micDeniedSheet(context, what: 'to record voice notes');
      return;
    }
    if (!mounted) {
      await recorder.dispose();
      return;
    }
    _haptic(HapticFeedback.mediumImpact);
    setState(() {
      _voiceRecorder = recorder;
      _recordingVoiceNote = true;
    });
  }

  Widget _voiceNotePill() {
    final recorder = _voiceRecorder;
    if (recorder == null) return _composerRow();
    return VoiceNotePill(
      recorder: recorder,
      onDiscard: _discardVoiceNote,
      onFinished: _finishVoiceNote,
    );
  }

  /// The pill cancelled the recording; just flip state and clean up.
  Future<void> _discardVoiceNote() async {
    final recorder = _voiceRecorder;
    _voiceRecorder = null;
    if (mounted) setState(() => _recordingVoiceNote = false);
    try {
      await recorder?.dispose();
    } catch (_) {}
    _haptic(HapticFeedback.lightImpact);
  }

  /// The pill stopped the recorder and handed over the file: transcribe
  /// it and drop the text into the composer for editing. Never
  /// auto-sends — transcription errors are common.
  Future<void> _finishVoiceNote(String path) async {
    final recorder = _voiceRecorder;
    _voiceRecorder = null;
    if (mounted) {
      setState(() {
        _recordingVoiceNote = false;
        _transcribing = true;
      });
    }
    _haptic(HapticFeedback.mediumImpact);
    try {
      final bytes = await File(path).readAsBytes();
      await File(path).delete();
      if (bytes.isEmpty) {
        if (mounted) toast(context, 'That recording was empty.');
        return;
      }
      final transcript = await widget.api.transcribeAudio(bytes);
      if (!mounted) return;
      final cur = _composer.text.trim();
      _composer.text = cur.isEmpty ? transcript : '$cur $transcript';
      _composer.selection = TextSelection.fromPosition(
          TextPosition(offset: _composer.text.length));
      _composerFocus.requestFocus();
      toast(context, 'Transcribed — review before sending.');
    } on PantheonApiException {
      // Keep the raw server body out of the toast: it can carry config
      // hints and provider errors the user can't act on from here.
      if (mounted) toast(context, "Couldn't transcribe the voice note.");
    } catch (_) {
      if (mounted) toast(context, "Couldn't transcribe the voice note.");
    } finally {
      if (mounted) setState(() => _transcribing = false);
      try {
        await recorder?.dispose();
      } catch (_) {}
    }
  }

  Widget _transcribingRow() {
    return Container(
      decoration: BoxDecoration(
        color: P.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: P.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Text('Transcribing voice note…', style: PT.meta),
        ],
      ),
    );
  }

  /// Slim status row shown above the composer while `/compress` runs.
  /// Compression is a slow LLM round-trip with no progress events, so
  /// this is the only in-flight signal the user gets.
  Widget _compressingRow() {
    return Container(
      decoration: BoxDecoration(
        color: P.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: P.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Text('Compressing context…', style: PT.meta),
        ],
      ),
    );
  }

  // ------------------------------------------------------- attachments --

  /// "Add to Chat" bottom sheet: camera, photo library, files.
  Future<void> _addSheet() async {
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
              const SizedBox(height: 12),
              Text('Add to Chat', style: PT.sectionTitle),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _addTile(Icons.photo_camera_rounded, 'Camera',
                        () => Navigator.pop(context, 'camera')),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _addTile(Icons.photo_library_rounded, 'Photos',
                        () => Navigator.pop(context, 'photos')),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _addRowTile(
                Icons.attach_file_rounded,
                'Add files',
                'Documents and other files',
                () => Navigator.pop(context, 'files'),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case 'camera':
        await _pickImages(ImageSource.camera);
      case 'photos':
        await _pickImages(ImageSource.gallery);
      case 'files':
        await _pickFiles();
    }
  }

  Widget _addTile(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: P.surface,
          borderRadius: BorderRadius.circular(P.r16),
          border: Border.all(color: P.border),
        ),
        child: Column(
          children: [
            Icon(icon, size: 28, color: P.accent, weight: 1.6),
            const SizedBox(height: 8),
            Text(label, style: PT.body.copyWith(fontSize: 14)),
          ],
        ),
      ),
    );
  }

  Widget _addRowTile(
      IconData icon, String title, String subtitle, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: P.surface,
          borderRadius: BorderRadius.circular(P.r16),
          border: Border.all(color: P.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: P.accent, weight: 1.6),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: PT.body.copyWith(fontSize: 14)),
                  Text(subtitle, style: PT.meta),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: P.inkFaint),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImages(ImageSource source) async {
    try {
      final picker = ImagePicker();
      if (source == ImageSource.gallery) {
        // Multiple media: images and videos in one pick, like the
        // reference app's multi-file handling.
        final files = await picker.pickMultipleMedia(imageQuality: 85);
        for (final f in files) {
          await _stageUpload(f.path, await f.readAsBytes());
        }
      } else {
        final f =
            await picker.pickImage(source: source, imageQuality: 85);
        if (f != null) await _stageUpload(f.path, await f.readAsBytes());
      }
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  Future<void> _pickFiles() async {
    try {
      final result =
          await FilePicker.platform.pickFiles(allowMultiple: true);
      if (result == null) return;
      for (final f in result.files) {
        if (f.path != null) {
          await _stageUpload(f.path!, await File(f.path!).readAsBytes());
        } else if (f.bytes != null) {
          await _stageUpload(f.name, f.bytes!);
        }
      }
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  /// Stage a picked file: show the chip immediately, upload in the
  /// background, then fill in the record (or the error).
  Future<void> _stageUpload(String path, List<int> bytes) async {
    final name = path.split('/').last.split('\\').last;
    final pending = _PendingAttachment(name: name, localPath: path);
    setState(() => _attachments.add(pending));
    await _runUpload(pending, bytes);
  }

  /// Retry a failed upload in place: re-reads the bytes from the retained
  /// local path and uploads again on the same chip.
  Future<void> _retryUpload(_PendingAttachment pending) async {
    final path = pending.localPath;
    if (path == null || path.isEmpty) {
      toast(context, 'Original file is gone — pick it again.');
      return;
    }
    List<int> bytes;
    try {
      bytes = await File(path).readAsBytes();
    } catch (e) {
      toastError(context, 'Could not re-read the file: $e');
      return;
    }
    await _runUpload(pending, bytes);
  }

  Future<void> _runUpload(_PendingAttachment pending, List<int> bytes) async {
    final name = pending.name;
    setState(() {
      pending.error = null;
      pending.record = null;
    });
    // A dedicated client per upload: removing the chip closes it and
    // aborts the in-flight request instead of letting the bytes land on
    // the server anyway.
    final client = http.Client();
    pending.uploadClient = client;
    try {
      final record = await widget.api.uploadAttachment(
        name: name.isEmpty ? 'file' : name,
        mime: _mimeFor(name),
        bytes: bytes,
        client: client,
      );
      if (!mounted) return;
      // The chip was removed mid-flight: the upload was aborted, and
      // the late response must not resurrect it or fire a toast.
      if (pending.cancelled || !_attachments.contains(pending)) return;
      setState(() => pending.record = record);
    } catch (e) {
      if (!mounted) return;
      if (pending.cancelled || !_attachments.contains(pending)) return;
      setState(() => pending.error = e.toString());
      toastError(context, e);
    } finally {
      pending.uploadClient = null;
      client.close();
    }
  }

  /// Remove a staged attachment. If its upload is still in flight the
  /// request is aborted first, so the file never lands on the server
  /// after the user removed it.
  void _removeAttachment(_PendingAttachment a) {
    a.cancelled = true;
    try {
      a.uploadClient?.close();
    } catch (_) {}
    setState(() => _attachments.remove(a));
  }

  String _mimeFor(String name) {
    final parts = name.toLowerCase().split('.');
    final ext = parts.length > 1 ? parts.last : '';
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'heic' => 'image/heic',
      'mp4' || 'mov' => 'video/mp4',
      'mp3' => 'audio/mpeg',
      'wav' => 'audio/wav',
      'm4a' => 'audio/mp4',
      'pdf' => 'application/pdf',
      'txt' || 'md' => 'text/plain',
      'json' => 'application/json',
      'zip' => 'application/zip',
      _ => 'application/octet-stream',
    };
  }

  Widget _attachmentChips() {
    // Horizontal scrollable card strip (reference-app style): thumbnails
    // for media, extension tiles for documents, X on each card.
    if (_attachments.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 108,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _attachments.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => _attachmentCard(_attachments[i]),
      ),
    );
  }

  Widget _attachmentCard(_PendingAttachment a) {
    final failed = a.error != null;
    final tile = SizedBox(
      width: 76,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              _pendingTile(a),
              Positioned(
                top: 2,
                right: 2,
                child: GestureDetector(
                  onTap: () => _removeAttachment(a),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close_rounded,
                        size: 12, color: Colors.white),
                  ),
                ),
              ),
              if (failed)
                Positioned(
                  bottom: 2,
                  right: 2,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: P.err,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.refresh_rounded,
                        size: 12, color: Colors.white),
                  ),
                ),
              if (a.uploading)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(P.r12),
                    ),
                    alignment: Alignment.center,
                    child: const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            failed ? 'tap to retry' : a.name,
            style: PT.faint.copyWith(
                color: failed ? P.err : P.inkFaint),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
    // A failed chip retries the upload in place; the X still removes it.
    if (failed && !a.uploading) {
      return GestureDetector(
        onTap: () => _retryUpload(a),
        child: tile,
      );
    }
    return tile;
  }

  /// The 72px tile for a pending attachment: local image thumbnail,
  /// play tile for video, extension tile for documents.
  Widget _pendingTile(_PendingAttachment a) {
    final hasError = a.error != null;
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: P.surface,
        borderRadius: BorderRadius.circular(P.r12),
        border: Border.all(color: hasError ? P.err : P.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(P.r12 - 1),
        child: _pendingTileBody(a),
      ),
    );
  }

  Widget _pendingTileBody(_PendingAttachment a) {
    if (a.isImage && a.localPath != null) {
      return Image.file(
        File(a.localPath!),
        width: 72,
        height: 72,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _extTile(a),
      );
    }
    if (a.isVideo) {
      return Container(
        color: P.ink,
        alignment: Alignment.center,
        child: const Icon(Icons.play_arrow_rounded,
            size: 28, color: Colors.white),
      );
    }
    return _extTile(a);
  }

  /// Document tile: extension label (ZIP, PDF, …) like the reference.
  Widget _extTile(_PendingAttachment a) {
    final ext = _extLabel(a.name);
    return Container(
      color: P.accentSoft,
      alignment: Alignment.center,
      child: Text(
        ext,
        style: PT.monoSm.copyWith(
            color: P.accent, fontWeight: FontWeight.w700),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  /// Uppercase extension label for a document tile, e.g. "ZIP".
  static String _extLabel(String name) {
    final parts = name.split('.');
    if (parts.length < 2) return 'FILE';
    final ext = parts.last.toUpperCase();
    return ext.length > 4 ? ext.substring(0, 4) : ext;
  }

  /// 2-column thumbnail grid under a sent user message (reference-app
  /// style). More than 4 attachments collapses the 4th tile into a "+N"
  /// overflow tile.
  Widget _sentAttachmentGrid(List<_SentAttachment> atts) {
    final shown = atts.take(4).toList();
    final overflow = atts.length - shown.length;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        itemCount: shown.length,
        itemBuilder: (_, i) {
          final a = shown[i];
          final extra =
              (i == shown.length - 1 && overflow > 0) ? overflow : 0;
          return _sentTile(a, overflowCount: extra, all: atts);
        },
      ),
    );
  }

  Widget _sentTile(_SentAttachment a,
      {int overflowCount = 0, List<_SentAttachment>? all}) {
    final Widget body;
    if (a.isImage && a.openable) {
      body = _SentThumb(future: _thumbFuture(a.id!), name: a.name);
    } else if (a.isVideo) {
      body = _sentDocTile(a, Icons.play_arrow_rounded);
    } else {
      body = _sentDocTile(a, null);
    }
    final tile = ClipRRect(
      borderRadius: BorderRadius.circular(P.r12),
      child: Container(
        color: P.surface,
        child: Stack(
          fit: StackFit.expand,
          children: [
            body,
            if (overflowCount > 0)
              Container(
                color: Colors.black54,
                alignment: Alignment.center,
                child: Text('+$overflowCount',
                    style: PT.body.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700)),
              ),
          ],
        ),
      ),
    );
    // The +N overflow tile opens a sheet with every attachment so the
    // hidden ones stay reachable.
    if (overflowCount > 0 && all != null) {
      return GestureDetector(
        onTap: () => _allAttachmentsSheet(all),
        child: tile,
      );
    }
    // Attachments from old messages (no id) have nothing to open.
    if (!a.openable) return tile;
    return GestureDetector(
      onTap: () => _openSentAttachment(a),
      child: tile,
    );
  }

  /// Bottom sheet listing every attachment on a message, so the ones
  /// hidden behind the +N overflow tile stay reachable.
  Future<void> _allAttachmentsSheet(List<_SentAttachment> atts) async {
    await showPSheet(
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
              Text('${atts.length} attachments', style: PT.sectionTitle),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: atts.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final a = atts[i];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(P.r12),
                        side: BorderSide(color: P.border),
                      ),
                      leading: Icon(
                        a.isImage
                            ? Icons.image_outlined
                            : a.isVideo
                                ? Icons.play_arrow_rounded
                                : Icons.insert_drive_file_outlined,
                        color: P.inkSecondary,
                      ),
                      title: Text(a.name,
                          style: PT.body,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      subtitle: Text(_extLabel(a.name),
                          style: PT.meta),
                      trailing: a.openable
                          ? const Icon(Icons.open_in_new_rounded,
                              color: P.inkMuted)
                          : null,
                      onTap: a.openable
                          ? () {
                              Navigator.pop(context);
                              _openSentAttachment(a);
                            }
                          : null,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Document/video tile: extension label or play glyph plus filename.
  Widget _sentDocTile(_SentAttachment a, IconData? icon) {
    return Container(
      color: P.accentSoft,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null)
            Icon(icon, size: 32, color: P.accent, weight: 1.6)
          else
            Text(_extLabel(a.name),
                style: PT.monoSm.copyWith(
                    color: P.accent, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(a.name,
                style: PT.faint,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }

  /// Memoized thumbnail bytes for a sent image, `GET /api/uploads/:id`.
  Future<Uint8List> _thumbFuture(String id) =>
      _thumbFutures.putIfAbsent(id,
          () => widget.api.downloadUpload(id).then(Uint8List.fromList));

  /// Attachments currently being opened: double-taps on a tile are
  /// ignored instead of opening the viewer twice.
  final Set<String> _openingIds = {};

  /// Open a sent attachment: images in the in-app full-screen viewer,
  /// video and documents via the system app (downloaded to temp first).
  Future<void> _openSentAttachment(_SentAttachment a) async {
    if (!a.openable) return;
    final id = a.id!;
    if (!_openingIds.add(id)) return;
    try {
      await _openSentAttachmentInner(a);
    } finally {
      _openingIds.remove(id);
    }
  }

  Future<void> _openSentAttachmentInner(_SentAttachment a) async {
    _haptic(HapticFeedback.lightImpact);
    if (a.isImage) {
      Uint8List bytes;
      try {
        bytes = await _thumbFuture(a.id!);
      } catch (e) {
        if (mounted) toastError(context, e);
        return;
      }
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => _ImageViewerDialog(bytes: bytes, name: a.name),
      );
      return;
    }
    try {
      final bytes = await widget.api.downloadUpload(a.id!);
      final dir = await getTemporaryDirectory();
      final safe = a.name.replaceAll(RegExp(r'[^\w\-. ]'), '_');
      final file = File('${dir.path}/pantheon_$safe');
      await file.writeAsBytes(bytes, flush: true);
      final res = await OpenFilex.open(file.path);
      if (res.type != ResultType.done && mounted) {
        toast(context, 'Could not open ${a.name}.');
      }
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  /// Insert a `> quoted` block at the end of the composer (long-press →
  /// Quote in reply).
  void _quoteInReply(String text) {
    final quoted =
        text.trim().split('\n').map((l) => '> $l').join('\n');
    final cur = _composer.text;
    _composer.text = cur.isEmpty ? '$quoted\n\n' : '$cur\n$quoted\n\n';
    _composer.selection =
        TextSelection.collapsed(offset: _composer.text.length);
    FocusScope.of(context).requestFocus(_composerFocus);
  }

  /// Haptic feedback, gated by the Appearance toggle.
  void _haptic(Future<void> Function() feedback) {
    if (AppPreferences.instance.hapticsEnabled.value) feedback();
  }

  Widget _bubble(TranscriptItem t) {
    final prefs = AppPreferences.instance;
    // Chat layout: 'default' = assistant runs full-bleed, user in bubbles;
    // 'bubbles' = iOS-style bubbles on both sides.
    final bubbles = prefs.bubbleStyle.value != 'default';
    final compactChat = prefs.chatDensity.value == 'compact';
    final vPad = compactChat ? 6.0 : 10.0;
    final hPad = compactChat ? 10.0 : 14.0;

    Widget core;
    bool isUser = false;
    if (t.type == 'reasoning') {
      core = _ThinkingBlock(content: t.content);
    } else {
      isUser = t.role == 'user';
      final isTool = t.role == 'tool';
      // Sent attachments: parsed from the raw block, rendered as the
      // thumbnail grid below the text (the block itself is stripped).
      final sentAtts = isUser
          ? _parseSentAttachments(t.content)
          : const <_SentAttachment>[];
      final msg = MessageContent(
        text: isUser ? t.content.replaceFirst(_attachmentBlock, '') : t.content,
        textStyle: PT.body
            .copyWith(fontSize: 14, color: isUser ? Colors.white : P.ink),
        onQuote: _quoteInReply,
        api: widget.api,
      );
      final body = <Widget>[msg];
      if (sentAtts.isNotEmpty) body.add(_sentAttachmentGrid(sentAtts));
      final header = Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AgentAvatar(size: 22),
            const SizedBox(width: 8),
            Text((t.role ?? 'assistant').toUpperCase(),
                style: PT.monoEyebrow
                    .copyWith(color: isTool ? P.info : P.accent)),
          ],
        ),
      );
      if (!isUser && !bubbles) {
        // Default layout: assistant/tool messages run edge to edge, no bubble.
        core = Container(
          margin: EdgeInsets.only(bottom: vPad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [header, ...body],
          ),
        );
      } else {
        core = Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: EdgeInsets.only(bottom: vPad),
            padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
            constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.85),
            decoration: BoxDecoration(
              gradient: isUser ? P.gradient : null,
              color: isUser
                  ? null
                  : isTool
                      ? P.tonal
                      : P.surface,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(P.r18),
                topRight: Radius.circular(P.r18),
                bottomLeft: Radius.circular(isUser ? P.r18 : P.r4),
                bottomRight: Radius.circular(isUser ? P.r4 : P.r18),
              ),
              border: isUser ? null : Border.all(color: P.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isUser) header,
                ...body,
              ],
            ),
          ),
        );
      }
    }

    // Optional per-message timestamp (only when the item carries one —
    // older transcript entries may omit it).
    if (!prefs.showTimestamps.value || t.tsMs == null) return core;
    final label = prefs.timestampFormat.value == 'absolute'
        ? clockTime(t.tsMs!)
        : timeAgo(t.tsMs!);
    return Column(
      crossAxisAlignment:
          isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        core,
        Padding(
          padding: const EdgeInsets.only(left: 4, right: 4, bottom: 8),
          child: Text(label, style: PT.faint),
        ),
      ],
    );
  }

  /// A day divider row for the chat list ("Today", "Yesterday", "Sep 28").
  Widget _dateDivider(DateTime day) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(dayLabel(day), style: PT.faint),
          ),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }

  /// Timeline tab: one dark card with a header block (title, status
  /// chip + outcome time, and the outcome detail as a separated block
  /// for failed/canceled runs), then MAIN / SUBAGENT NN sections whose
  /// rows hang off a dashed rail with status glyphs. Rows expand on
  /// tap. Detail lines only render when they have real content —
  /// empty strings never produce a line.
  Widget _timeline(PantheonRun run) {
    if (run.timeline.isEmpty) {
      return const EmptyState(
        icon: Icons.timeline_rounded,
        title: 'No timeline events',
        body: 'Run events will stream in here.',
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: StaggerItem(
        index: 0,
        child: Container(
          decoration: BoxDecoration(
            color: P.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: P.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _timelineHeader(run),
              ..._timelineBlocks(run),
            ],
          ),
        ),
      ),
    );
  }

  /// Card header: title, status chip + outcome time, and the outcome
  /// detail as a separated paragraph when it exists.
  Widget _timelineHeader(PantheonRun run) {
    TimelineItem? terminal;
    for (final e in run.timeline) {
      if (_isTerminalKind(e.kind)) terminal = e;
    }
    final detail = (terminal?.detail ?? '').trim();
    final outcomeTs = terminal?.tsMs ?? run.createdMs;

    String label;
    Color color;
    if (run.status == 'failed') {
      label = 'Error';
      color = P.err;
    } else if (run.status == 'canceled') {
      label = 'Canceled';
      color = P.err;
    } else if (run.status == 'awaiting_approval') {
      label = 'Awaiting approval';
      color = P.warn;
    } else if (run.status == 'running') {
      label = 'Live';
      color = P.accent;
    } else if (run.status == 'completed') {
      label = 'Completed';
      color = P.ok;
    } else {
      label = run.status;
      color = P.inkMuted;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            run.title.trim().isNotEmpty ? run.title.trim() : 'Session',
            style: PT.cardTitle.copyWith(fontSize: 19),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: color.withValues(alpha: 0.45)),
                ),
                child: Text(label,
                    style: PT.label.copyWith(fontSize: 12, color: color)),
              ),
              const SizedBox(width: 10),
              Text(_clockTime(outcomeTs), style: PT.meta),
            ],
          ),
          if (detail.isNotEmpty) ...[
            const SizedBox(height: 12),
             Divider(color: P.divider, height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: SelectableText(detail,
                  style: PT.body.copyWith(
                      fontSize: 13.5, color: P.inkSecondary)),
            ),
          ],
          if (run.status == 'failed') ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _retrying ? null : _retryRun,
                icon: _retrying
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded, size: 18),
                label: Text(_retrying ? 'Retrying…' : 'Retry turn'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: P.accent,
                  side: BorderSide(color: P.accent.withValues(alpha: 0.5)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Timeline body: section headers plus rows. Subagent spans become
  /// numbered SUBAGENT sections; everything else is MAIN. A row draws
  /// its dashed rail only when the next block is a plain row (no
  /// section header in between).
  List<Widget> _timelineBlocks(PantheonRun run) {
    final segments = <_TlSegment>[];
    var subagents = 0;
    var inSubagent = false;
    var mainAdded = false;
    for (final e in run.timeline) {
      String? section;
      String? subtitle;
      if (_isAgentKind(e.kind)) {
        if (!inSubagent) {
          subagents++;
          final agent = (e.detail ?? '').trim();
          section =
              'SUBAGENT ${subagents.toString().padLeft(2, '0')}';
          subtitle = agent.isNotEmpty ? agent : null;
          inSubagent = true;
        }
      } else {
        inSubagent = false;
        if (!mainAdded) {
          section = 'MAIN';
          mainAdded = true;
        }
      }
      segments.add(
          _TlSegment(section: section, subtitle: subtitle, item: e));
    }
    final blocks = <Widget>[];
    for (var i = 0; i < segments.length; i++) {
      final s = segments[i];
      if (s.section != null) {
        blocks.add(_timelineSection(s.section!, subtitle: s.subtitle));
      }
      final next = i + 1 < segments.length ? segments[i + 1] : null;
      blocks.add(_timelineRow(s.item,
          showRail: next != null && next.section == null));
    }
    return blocks;
  }

  Widget _timelineSection(String label, {String? subtitle}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
         Divider(color: P.divider, height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(label,
                    style: PT.label.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                        color: P.inkSecondary)),
              ),
              if (subtitle != null)
                Flexible(
                  child: Text(subtitle,
                      style: PT.meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _timelineRow(TimelineItem item, {required bool showRail}) {
    final expanded = _expandedTl.contains(item.seq);
    final detail = (item.detail ?? '').trim();
    final spec = _tlGlyph(item.kind);
    final body = IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              const SizedBox(height: 2),
              _GlyphCircle(icon: spec.icon, color: spec.color),
              if (showRail) const Expanded(child: _DashedRail()),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_tlTitle(item.kind),
                      style: PT.body.copyWith(
                          fontSize: 14.5, fontWeight: FontWeight.w600)),
                  if (detail.isNotEmpty && !expanded)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(detail,
                          style: PT.meta,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis),
                    ),
                  if (expanded) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: SelectableText(detail,
                          style: PT.body.copyWith(
                              fontSize: 13.5, color: P.inkSecondary)),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(timeAgo(item.tsMs), style: PT.faint),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (detail.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                  expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.chevron_right_rounded,
                  color: P.inkMuted,
                  size: 20),
            ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 14, 10),
      child: detail.isEmpty
          ? body
          : InkWell(
              onTap: () => setState(() => expanded
                  ? _expandedTl.remove(item.seq)
                  : _expandedTl.add(item.seq)),
              borderRadius: BorderRadius.circular(8),
              child: body,
            ),
    );
  }

  static bool _isAgentKind(String kind) =>
      kind == 'agent_spawned' ||
      kind == 'agent_message' ||
      kind == 'agent_completed';

  static bool _isTerminalKind(String kind) =>
      kind == 'run_failed' ||
      kind == 'run_canceled' ||
      kind == 'run_completed';

  /// Status glyph for a timeline kind.
  _GlyphSpec _tlGlyph(String kind) {
    switch (kind) {
      case 'run_completed':
      case 'turn_completed':
      case 'agent_completed':
      case 'approval_granted':
      case 'model_completed':
        return _GlyphSpec(Icons.check_rounded, P.ok);
      case 'run_failed':
      case 'approval_denied':
        return _GlyphSpec(Icons.close_rounded, P.err);
      case 'run_canceled':
        return _GlyphSpec(Icons.close_rounded, P.warn);
      case 'approval_requested':
      case 'turn_parked':
        return _GlyphSpec(Icons.schedule_rounded, P.warn);
      case 'input_requested':
        return _GlyphSpec(Icons.question_answer_rounded, P.accent);
      case 'input_provided':
        return _GlyphSpec(Icons.check_rounded, P.ok);
      case 'agent_spawned':
        return _GlyphSpec(Icons.person_add_alt_rounded, P.info);
      case 'agent_message':
        return _GlyphSpec(Icons.chat_bubble_outline_rounded, P.info);
      case 'titled':
        return _GlyphSpec(Icons.edit_rounded, P.inkMuted);
      case 'usage':
        return _GlyphSpec(Icons.pie_chart_outline_rounded, P.inkMuted);
      case 'run_started':
      case 'turn_started':
      case 'model_requested':
        return _GlyphSpec(Icons.fiber_manual_record_rounded, P.accent);
      case 'tool_started':
        return _GlyphSpec(Icons.build_rounded, P.accent);
      case 'tool_completed':
        return _GlyphSpec(Icons.check_rounded, P.ok);
      case 'model_fallback':
        return _GlyphSpec(Icons.swap_horiz_rounded, P.warn);
      default:
        return _GlyphSpec(Icons.info_outline_rounded, P.inkMuted);
    }
  }

  /// Bold row title for a timeline kind. Unknown kinds are humanized;
  /// raw snake_case never reaches the screen.
  String _tlTitle(String kind) {
    switch (kind) {
      case 'run_started':
        return 'Session started';
      case 'run_completed':
        return 'Run completed';
      case 'run_failed':
        return 'Run failed';
      case 'run_canceled':
        return 'Run canceled';
      case 'turn_started':
        return 'Turn started';
      case 'turn_completed':
        return 'Turn completed';
      case 'turn_parked':
        return 'Turn parked';
      case 'model_requested':
        return 'Model request';
      case 'model_completed':
        return 'Model response';
      case 'usage':
        return 'Usage';
      case 'approval_requested':
        return 'Approval requested';
      case 'approval_granted':
        return 'Approval granted';
      case 'approval_denied':
        return 'Approval denied';
      case 'input_requested':
        return 'Clarification needed';
      case 'input_provided':
        return 'Clarification answered';
      case 'agent_spawned':
        return 'Subagent started';
      case 'agent_message':
        return 'Subagent update';
      case 'agent_completed':
        return 'Subagent finished';
      case 'titled':
        return 'Session renamed';
      case 'tool_started':
        return 'Tool started';
      case 'tool_completed':
        return 'Tool finished';
      case 'model_fallback':
        return 'Model fallback';
      default:
        final words = kind.replaceAll('_', ' ').trim();
        if (words.isEmpty) return 'Event';
        return words[0].toUpperCase() + words.substring(1);
    }
  }

  /// Clock time like "10:29pm".
  String _clockTime(int tsMs) {
    final dt = DateTime.fromMillisecondsSinceEpoch(tsMs);
    final h12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$h12:$mm${dt.hour < 12 ? 'am' : 'pm'}';
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

/// One timeline row plus the section header (if any) that precedes it.
class _TlSegment {
  final String? section;
  final String? subtitle;
  final TimelineItem item;
  const _TlSegment({this.section, this.subtitle, required this.item});
}

/// Status glyph spec for a timeline kind.
class _GlyphSpec {
  final IconData icon;
  final Color color;
  const _GlyphSpec(this.icon, this.color);
}

/// The status glyph: tinted circle with an icon.
class _GlyphCircle extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _GlyphCircle({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.13),
        border: Border.all(color: color.withValues(alpha: 0.55), width: 1.2),
      ),
      child: Icon(icon, size: 13, color: color),
    );
  }
}

/// Thin dashed vertical rail connecting timeline glyphs.
class _DashedRail extends StatelessWidget {
  const _DashedRail();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => CustomPaint(
        size: Size(2, constraints.maxHeight),
        painter: _DashPainter(),
      ),
    );
  }
}

class _DashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = P.borderStrong
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    const dashH = 5.0;
    const gapH = 5.0;
    var y = 2.0;
    while (y < size.height - 2) {
      final end = (y + dashH).clamp(0.0, size.height);
      canvas.drawLine(
          Offset(size.width / 2, y), Offset(size.width / 2, end), paint);
      y += dashH + gapH;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// A reasoning trace as a collapsible block, collapsed by default.
/// Tap the header to expand the full deliberation.
class _ThinkingBlock extends StatefulWidget {
  final String content;

  const _ThinkingBlock({required this.content});

  @override
  State<_ThinkingBlock> createState() => _ThinkingBlockState();
}

class _ThinkingBlockState extends State<_ThinkingBlock> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    // Slim foldable row: icon + label + chevron, expanding to the content.
    // Collapsed by default; far less visual weight than a card.
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => setState(() => _open = !_open),
              borderRadius: BorderRadius.circular(P.r8),
              splashColor: P.accentSoft,
              highlightColor: P.accentSoft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Row(
                  children: [
                    const Icon(Icons.psychology_outlined,
                        size: 14, color: P.inkFaint),
                    const SizedBox(width: 8),
                    Text('Thinking',
                        style: PT.meta.copyWith(color: P.inkFaint)),
                    const Spacer(),
                    Icon(
                        _open
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        size: 16,
                        color: P.inkFaint),
                  ],
                ),
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
              child: MessageContent(
                text: widget.content,
                textStyle: PT.small.copyWith(
                    fontStyle: FontStyle.italic, color: P.inkMuted),
              ),
            ),
        ],
      ),
    );
  }
}

/// The send-button in-flight glyph, honoring the Appearance loading-style
/// choice (spinner / dots / pulse).
class _SendGlyph extends StatelessWidget {
  const _SendGlyph();

  @override
  Widget build(BuildContext context) {
    switch (AppPreferences.instance.loadingStyle.value) {
      case 'dots':
        return const DotsLoading(color: Colors.white, size: 5);
      case 'pulse':
        return const PulseLoading(color: Colors.white, size: 12);
      default:
        return const CircularProgressIndicator(
            strokeWidth: 2.5, color: Colors.white);
    }
  }
}

/// Red Nyx sheet button for the hard "Stop the model" action. Mirrors
/// the private `_DangerButton` in widgets/forms.dart (danger wash fill,
/// 52dp tall, 20dp radius).
class _DangerSheetButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _DangerSheetButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: P.err.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(P.r20),
          border: Border.all(color: P.err.withValues(alpha: 0.5)),
        ),
        alignment: Alignment.center,
        child: Text(label,
            style: PT.label.copyWith(color: P.err, fontSize: 15)),
      ),
    );
  }
}

/// A file staged on the composer. `record` is null while the upload is
/// still in flight; `error` is set when the upload failed.
class _PendingAttachment {
  final String name;
  final String? localPath;
  UploadRecord? record;
  String? error;

  /// Set when the user removed the chip while its upload was in flight.
  /// The late response must not resurrect the chip or toast about it.
  bool cancelled = false;

  /// The dedicated HTTP client for the in-flight upload; closing it
  /// aborts the request so removed files never land on the server.
  http.Client? uploadClient;

  _PendingAttachment({required this.name, this.localPath});

  bool get uploading => record == null && error == null;
  bool get isImage =>
      (record?.isImage ?? false) ||
      _imageExts.any((e) => name.toLowerCase().endsWith(e));
  bool get isVideo =>
      (record?.mime.startsWith('video/') ?? false) ||
      _videoExts.any((e) => name.toLowerCase().endsWith(e));

  static const _imageExts = [
    '.jpg',
    '.jpeg',
    '.png',
    '.gif',
    '.webp',
    '.heic'
  ];
  static const _videoExts = ['.mp4', '.mov', '.m4v'];
}

/// One attachment parsed out of a sent message's `[attachments]` block.
class _SentAttachment {
  final String name;
  final String mime;
  final String? id;

  _SentAttachment({required this.name, required this.mime, this.id});

  bool get isImage => mime.startsWith('image/');
  bool get isVideo => mime.startsWith('video/');
  bool get openable => id != null && id!.isNotEmpty;
}

/// Thumbnail for a sent image attachment: spinner while loading, glyph
/// on failure, cover-fit image once the bytes arrive.
class _SentThumb extends StatelessWidget {
  final Future<Uint8List> future;
  final String name;

  const _SentThumb({required this.future, required this.name});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: future,
      builder: (_, snap) {
        if (snap.hasData) {
          return Image.memory(
            snap.data!,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const _ThumbError(),
          );
        }
        if (snap.hasError) return const _ThumbError();
        return Container(
          color: P.surface,
          alignment: Alignment.center,
          child: const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: P.accent),
          ),
        );
      },
    );
  }
}

class _ThumbError extends StatelessWidget {
  const _ThumbError();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: P.surface,
      alignment: Alignment.center,
      child: const Icon(Icons.broken_image_outlined,
          size: 28, color: P.inkFaint),
    );
  }
}

/// Full-screen image viewer for a sent attachment: pinch-to-zoom via
/// InteractiveViewer, close button, filename caption. No plugin needed.
class _ImageViewerDialog extends StatelessWidget {
  final Uint8List bytes;
  final String name;

  const _ImageViewerDialog({required this.bytes, required this.name});

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: EdgeInsets.zero,
      child: Stack(
        children: [
          Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4,
              child: Image.memory(bytes),
            ),
          ),
          Positioned(
            top: pad.top + 8,
            left: 8,
            child: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              style:
                  IconButton.styleFrom(backgroundColor: Colors.black54),
            ),
          ),
          Positioned(
            bottom: pad.bottom + 16,
            left: 16,
            right: 16,
            child: Text(name,
                style: PT.small.copyWith(color: Colors.white70),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}
