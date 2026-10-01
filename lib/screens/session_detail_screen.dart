import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
import '../services/notification_service.dart';
import '../services/pantheon_api.dart';
import '../theme.dart';
import '../widgets/active_profile_avatar.dart';
import '../widgets/buttons.dart';
import '../widgets/chips.dart';
import '../widgets/export_sheet.dart';
import '../widgets/forms.dart';
import '../widgets/message_content.dart';
import '../widgets/new_chat_sheet.dart';
import '../widgets/session_timeline.dart';
import '../widgets/states.dart';
import '../widgets/team_run_view.dart';
import '../widgets/todos_sheet.dart';
import '../widgets/voice_note_pill.dart';
import 'agent_activity_screen.dart';
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

  /// Pre-filled composer draft (e.g. an error handed over from Logs).
  /// Applied once in initState; the user can edit before sending.
  final String? initialDraft;

  /// Indicator chip shown above the composer naming the expert team or
  /// standalone expert this session was opened for ("Use team" /
  /// "Use expert"). Tapping × dismisses the chip only; the session
  /// keeps running.
  final String? attachedName;

  /// Icon shown on the attached-team/expert chip.
  final IconData attachedIcon;

  /// When set, this session is a team run: a Team tab renders the
  /// staged swarm as a multi-agent conversation with per-expert
  /// attribution. The Chat tab stays the lead's primary thread.
  final String? swarmId;

  const SessionDetailScreen(
      {super.key,
      required this.api,
      required this.runId,
      this.pendingApprovals,
      this.initialDraft,
      this.attachedName,
      this.attachedIcon = Icons.groups_outlined,
      this.swarmId});

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

  /// Live-turn clock: anchor ms for the "Working for …" row, ticking
  /// once a second while the turn runs. See [_syncLiveClock].
  int? _liveSinceMs;
  Timer? _liveTicker;
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

  /// `provider · model · effort` from the `[model]` config section.
  String? _modelLine;

  /// How many of the run's queued messages were parked from this screen.
  /// The poller auto-drains the server queue oldest-first as turns
  /// settle, regardless of which screen or device parked each message;
  /// this counter only tracks the local share (used to reconcile the
  /// "Queued — sends when the turn settles." toast state). Steer resets
  /// this to 1 because it wipes the server queue and parks just the
  /// steered message.
  int _queuedByMe = 0;

  /// Whether the queue section lists its messages expanded.
  bool _queueExpanded = false;

  /// Edge detector for the approval-parked notification: the poller
  /// fires it once per parking, not once per tick.
  bool _wasParked = false;

  /// Retry of a failed turn is in flight.
  bool _retrying = false;

  /// The expert-team/expert indicator chip above the composer. Set from
  /// [SessionDetailScreen.attachedName]; dismissing it only hides the
  /// chip — the session keeps running.
  String? _attachedName;

  /// Attachments staged on the composer: picked locally, uploaded to
  /// `POST /api/uploads`, then sent with the message as attachment ids.
  final List<_PendingAttachment> _attachments = [];

  /// Memoized thumbnail futures for sent image attachments, keyed by
  /// upload id — `GET /api/uploads/:id` bytes cached per session.
  final Map<String, Future<Uint8List>> _thumbFutures = {};

  /// Voice-note recording state. The composer mic starts a recording
  /// (the pill); the composer also has its own mic — the AppBar no
  /// longer carries one (it now holds new-chat and options actions).
  bool _recordingVoiceNote = false;

  /// Collapsed header: hides the date/model line, mode/todos/context
  /// row and the stats block; the Chat/Timeline tab bar stays visible.
  /// Toggled from the header chevron or the options sheet.
  bool _headerCollapsed = false;

  /// Active agent/profile name for chat labels; 'Pantheon' until the
  /// config resolves (best-effort — the label never blocks the chat).
  String _agentName = 'Pantheon';

  /// True while a finished voice note is being transcribed.
  bool _transcribing = false;

  /// Recorder for the in-flight voice note; the pill drives it and the
  /// parent disposes it once the pill reports back.
  AudioRecorder? _voiceRecorder;

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
      final size = m.group(3)?.trim();
      final id = m.group(4)?.trim();
      if (name.isEmpty) continue;
      out.add(_SentAttachment(
        name: name,
        mime: mime.isEmpty ? 'application/octet-stream' : mime,
        id: (id == null || id.isEmpty) ? null : id,
        size: size?.isEmpty ?? true ? null : size,
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
    _attachedName = widget.attachedName;
    if (widget.initialDraft != null && widget.initialDraft!.isNotEmpty) {
      _composer.text = widget.initialDraft!;
    }
    _load(initial: true);
  }

  @override
  void dispose() {
    _poll?.cancel();
    _liveTicker?.cancel();
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
      final agentName = await _safeAgentName();
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
        _agentName = agentName;
        _runApprovals = approvals;
        _error = null;
        _loading = false;
      });
      _syncPolling(run.status);
      _syncLiveClock(run.status);
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

  /// `provider · model · effort` from the `[model]` config section; null
  /// when unreadable (the header falls back to the run's own fields).
  /// Effort is the `[model].reasoning` level, shown only when set and
  /// not "off".
  Future<String?> _safeModelLine() async {
    try {
      final doc = await widget.api.getConfig();
      final m = doc.values['model'];
      if (m is Map) {
        final p = m['provider']?.toString();
        final mod = m['model']?.toString();
        final reasoning = m['reasoning']?.toString();
        final parts = [
          if (p != null && p.isNotEmpty) p,
          if (mod != null && mod.isNotEmpty) mod,
          if (reasoning != null &&
              reasoning.isNotEmpty &&
              reasoning != 'off')
            reasoning,
        ];
        if (parts.isNotEmpty) return parts.join(' · ');
      }
    } catch (_) {}
    return null;
  }

  /// Active agent/profile name for the chat labels; 'Pantheon' when the
  /// config is unreadable or no agent is selected.
  Future<String> _safeAgentName() async {
    try {
      final doc = await widget.api.getConfig();
      final name = doc.activeAgent;
      if (name != null && name.isNotEmpty) return name;
    } catch (_) {}
    return 'Pantheon';
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
      _syncLiveClock(run.status);
      // Turn settled: haptic + auto-drain the oldest queued message,
      // whoever parked it (this screen, another screen, or another
      // device). The server pops the head of its FIFO queue on the
      // idle send, so the rest stay queued.
      if (wasLive && !_isLive(run.status)) {
        _haptic(HapticFeedback.lightImpact);
        // Alertable event: run completed / failed. The delivery path
        // consults the stored notification prefs (master, event toggle,
        // quiet hours, per-session mute) before showing anything.
        final settled = run.status;
        if (settled == 'completed' || settled == 'failed') {
          final label = run.title.isNotEmpty ? run.title : 'A run';
          final failed = settled == 'failed';
          unawaited(NotificationService.instance.notify(
            event: failed
                ? NotificationService.eventRunFailed
                : NotificationService.eventRunCompleted,
            sessionId: widget.runId,
            title: failed ? 'Run failed' : 'Run completed',
            body: '$label ${failed ? 'failed' : 'finished'}.',
          ));
        }
      }
      if (wasLive && !_isLive(run.status)) {
        final queue = run.queuedMessages;
        if (queue.isEmpty) {
          _queuedByMe = 0;
        } else {
          // Attempt the drain; on failure _drainQueueText keeps the
          // poller alive (turn-in-flight) so the next settle retries.
          if (await _drainQueueText(queue.first) && _queuedByMe > 0) {
            _queuedByMe--;
          }
          return;
        }
      }
      // Alertable event: freshly parked on approval — edge-triggered
      // so the poller fires it once per parking, not once per tick.
      final parked = run.status == 'awaiting_approval';
      if (parked && !_wasParked) {
        final label = run.title.isNotEmpty ? run.title : 'A run';
        unawaited(NotificationService.instance.notify(
          event: NotificationService.eventApprovalParked,
          sessionId: widget.runId,
          title: 'Approval needed',
          body: '$label is parked waiting for your decision.',
        ));
      }
      _wasParked = parked;
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
      // Keyboard-submit path while a turn is in flight (the button
      // itself stops on tap): offer the full in-flight sheet so a typed
      // draft can be steered or queued instead of dropped.
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

  /// In-flight task controls: exactly three actions — Stop current task
  /// (red, destructive hard stop), Steer current task (redirects the
  /// running turn with the composer's draft), Queue for next turn
  /// (parks the draft behind the running turn). Queue/steer need a
  /// draft and a genuinely running turn (a parked run 409s message
  /// sends until its approval is decided).
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
              Text('Task in flight', style: PT.sectionTitle),
              const SizedBox(height: 8),
              Text(
                'Stop the model, redirect it, or park this message behind it.',
                style: PT.small),
              const SizedBox(height: 20),
              _DangerSheetButton(
                label: 'Stop current task',
                onTap: () => Navigator.pop(context, 'stop'),
              ),
              const SizedBox(height: 12),
              Opacity(
                opacity: canQueue ? 1 : 0.4,
                child: TonalButton(
                  label: 'Steer current task',
                  onTap: canQueue
                      ? () => Navigator.pop(context, 'steer')
                      : null,
                ),
              ),
              const SizedBox(height: 12),
              Opacity(
                opacity: canQueue ? 1 : 0.4,
                child: TonalButton(
                  label: 'Queue for next turn',
                  onTap: canQueue
                      ? () => Navigator.pop(context, 'queue')
                      : null,
                ),
              ),
              if (!canQueue) ...[
                const SizedBox(height: 12),
                Text(
                  hasDraft
                      ? 'Queue and steer need a running turn.'
                      : 'Type a message to steer or queue it.',
                  style: PT.meta,
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case 'stop':
        await _hardStopTurn();
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
      DefaultTabController.of(context).animateTo(0);
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

  /// Muse-style agent profile entry: tap the agent avatar in chat to
  /// open the session-scoped activity view for this run.
  void _openAgentActivity() {
    final run = _run;
    if (run == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AgentActivityScreen(run: run, api: widget.api),
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
          icon:  Icon(Icons.chevron_left_rounded,
              size: 30, color: P.ink, weight: 1.6),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(title),
        actions: [
          IconButton(
            icon: Icon(Icons.edit_outlined,
                color: P.ink, weight: 1.6),
            tooltip: 'New chat',
            onPressed: () => showNewChatSheet(context, widget.api),
          ),
          IconButton(
            icon: Icon(Icons.more_horiz_rounded,
                color: P.ink, weight: 1.6),
            tooltip: 'Options',
            onPressed: _optionsSheet,
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
                  length: widget.swarmId != null ? 3 : 2,
                  child: Column(
                    children: [
                      _header(_run!),
                      TabBar(
                        tabs: [
                          const Tab(text: 'Chat'),
                          if (widget.swarmId != null) const Tab(text: 'Team'),
                          const Tab(text: 'Timeline')
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
                            if (widget.swarmId != null)
                              TeamRunView(
                                  api: widget.api,
                                  swarmId: widget.swarmId!),
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
              GestureDetector(
                onTap: () => setState(
                    () => _headerCollapsed = !_headerCollapsed),
                child: Padding(
                  padding: const EdgeInsets.only(left: 6, top: 2),
                  child: Icon(
                    _headerCollapsed
                        ? Icons.expand_more_rounded
                        : Icons.expand_less_rounded,
                    color: Colors.white.withValues(alpha: 0.85),
                    size: 24,
                  ),
                ),
              ),
            ],
          ),
          if (!_headerCollapsed) ...[
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
              Icon(Icons.schedule_rounded, size: 16, color: P.accent),
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
                      child: Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(Icons.edit_outlined,
                            size: 16, color: P.inkMuted),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _deleteQueueItem(i),
                      child: Padding(
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
    // Subagent pill placement is recomputed per build: the timeline
    // (and transcript) change on every poll.
    _pillSpans = null;
    DateTime? lastDay;
    void dividerFor(TranscriptItem t) {
      if (dividers && t.tsMs != null) {
        final d = DateTime.fromMillisecondsSinceEpoch(t.tsMs!);
        final day = DateTime(d.year, d.month, d.day);
        if (lastDay == null || day != lastDay) {
          rows.add(_dateDivider(day));
          lastDay = day;
        }
      }
    }

    // Interleaved streaming: the transcript renders in arrival order as
    // text message, Thoughts block, text message, Thoughts block, …
    // Consecutive thought items (reasoning, assistant tool-call rows
    // and their tool results) accumulate in a buffer; the buffer flushes
    // as one quiet "Thoughts >" row whenever a text message, a user
    // message, or the end of the transcript is reached.
    final thoughtItems = <TranscriptItem>[];
    final bufferedIndices = <int>[];
    final live = _isLive(_run?.status ?? '');
    void flushThoughts() {
      final indices = List<int>.from(bufferedIndices);
      final steps = _stepsFromItems(thoughtItems, indices);
      thoughtItems.clear();
      bufferedIndices.clear();
      if (steps.isNotEmpty) {
        rows.add(StaggerItem(
            index: indices.first,
            child: _thoughtsRow(steps, live)));
      }
      for (final bi in indices) {
        _maybeSubagentPill(rows, bi);
      }
    }

    var i = 0;
    while (i < _messages.length) {
      final t = _messages[i];
      dividerFor(t);
      if (t.role == 'user') {
        flushThoughts();
        rows.add(StaggerItem(index: i, child: _bubble(t)));
        _maybeSubagentPill(rows, i);
        i++;
        continue;
      }
      if (t.role == 'assistant' && t.toolCalls.isNotEmpty) {
        // Text and tool calls in one item: text first, calls into the
        // thoughts buffer (mirrors streaming order).
        if (t.content.trim().isNotEmpty) {
          flushThoughts();
          rows.add(StaggerItem(index: i, child: _bubble(_stripToolCalls(t))));
          _maybeSubagentPill(rows, i);
        }
        thoughtItems.add(t);
        bufferedIndices.add(i);
        i++;
        continue;
      }
      if (t.type == 'reasoning' || t.role == 'tool') {
        thoughtItems.add(t);
        bufferedIndices.add(i);
        i++;
        continue;
      }
      flushThoughts();
      rows.add(StaggerItem(index: i, child: _bubble(t)));
      _maybeSubagentPill(rows, i);
      i++;
    }
    flushThoughts();
    // Live-turn indicator: "Working for 1m 9s", ticking each second.
    if (_isLive(_run?.status ?? '') && _liveSinceMs != null) {
      rows.add(_workingRow());
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      itemCount: rows.length,
      itemBuilder: (context, i) => rows[i],
    );
  }

  /// Build Thought steps from one contiguous block of thought items:
  /// reasoning summaries and tool calls (with their results). Orphan
  /// tool results with no matching call row become their own step rather
  /// than a fake assistant bubble. [indices] are the transcript indices
  /// of [items], used to anchor subagent pills to the delegate step's
  /// transcript position.
  List<_ThoughtStep> _stepsFromItems(
      List<TranscriptItem> items, List<int> indices) {
    final live = _isLive(_run?.status ?? '');
    final results = <String, TranscriptItem>{};
    for (final t in items) {
      if (t.role == 'tool' && t.toolCallId != null) {
        results.putIfAbsent(t.toolCallId!, () => t);
      }
    }
    final steps = <_ThoughtStep>[];
    var k = 0;
    for (final t in items) {
      final idx = k < indices.length ? indices[k] : -1;
      k++;
      if (t.type == 'reasoning') {
        if (t.content.trim().isNotEmpty) {
          steps.add(_ThoughtStep.reasoning(t.content, idx));
        }
      } else if (t.role == 'assistant' && t.toolCalls.isNotEmpty) {
        for (final c in t.toolCalls) {
          steps.add(_ThoughtStep.tool(
            call: c,
            result: results[c.id],
            transcriptIndex: idx,
            live: live,
            ownerTsMs: t.tsMs,
          ));
        }
      } else if (t.role == 'tool') {
        final matched =
            steps.any((s) => !s.isReasoning && s.id == t.toolCallId);
        if (!matched) steps.add(_ThoughtStep.orphanResult(t, idx));
      }
    }
    return steps;
  }

  /// Subagent spans from the run timeline (the same source the agent
  /// activity view uses). A span is a maximal run of agent-kind events.
  List<_SubagentSpan> _subagentSpans() {
    final spans = <_SubagentSpan>[];
    var current = <TimelineItem>[];
    var inSpan = false;
    String? name;
    int? started;

    void close({int? endedMs}) {
      if (!inSpan) return;
      spans.add(_SubagentSpan(
        name: (name ?? '').isEmpty ? 'subagent' : name!,
        startedMs: started,
        endedMs: endedMs,
        items: current,
      ));
      current = <TimelineItem>[];
      inSpan = false;
      name = null;
      started = null;
    }

    for (final e in _run?.timeline ?? <TimelineItem>[]) {
      if (!tlIsAgentKind(e.kind)) {
        close();
        continue;
      }
      if (!inSpan) {
        inSpan = true;
        name = (e.detail ?? '').trim();
        started = e.tsMs;
      }
      current.add(e);
      if (e.kind == 'agent_completed') close(endedMs: e.tsMs);
    }
    close();
    return spans;
  }

  /// Map of transcript index → subagent spans whose work finished around
  /// that item. Computed lazily once per message list build.
  Map<int, List<_SubagentSpan>>? _pillSpans;

  void _maybeSubagentPill(List<Widget> rows, int msgIndex) {
    _pillSpans ??= _buildPillSpans();
    final spans = _pillSpans![msgIndex];
    if (spans == null || spans.isEmpty) return;
    rows.add(StaggerItem(index: msgIndex, child: _subagentPill(spans)));
  }

  Map<int, List<_SubagentSpan>> _buildPillSpans() {
    final map = <int, List<_SubagentSpan>>{};
    final spans = _subagentSpans();
    if (spans.isEmpty) return map;
    final last = _messages.length - 1;
    for (final s in spans) {
      final endMs = s.endedMs ?? s.startedMs;
      var idx = last;
      if (endMs != null) {
        idx = last;
        for (var k = _messages.length - 1; k >= 0; k--) {
          final ts = _messages[k].tsMs;
          if (ts != null && ts <= endMs) {
            idx = k;
            break;
          }
        }
      }
      map.putIfAbsent(idx, () => []).add(s);
    }
    return map;
  }

  /// Compact "N agent used" pill below the turn that used subagents.
  /// Tapping opens the subagents sheet.
  Widget _subagentPill(List<_SubagentSpan> spans) {
    final n = spans.length;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openSubagents(spans),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10, top: 2),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: P.border),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.hub_outlined,
                    size: 15, color: P.inkSecondary),
                const SizedBox(width: 8),
                Text(
                  '$n agent${n == 1 ? '' : 's'} used',
                  style: PT.small.copyWith(color: P.inkSecondary),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded,
                    size: 15, color: P.inkSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Near-full-screen sheet listing the turn's subagents: name, status
  /// with elapsed time, and its nested content (the span's timeline
  /// rows rendered as checklist rows, same visual language as the
  /// Thoughts sheet). Data is the run timeline — the same source the
  /// agent activity view uses; the backend does not expose subagent
  /// transcripts, so nothing is fabricated.
  void _openSubagents(List<_SubagentSpan> spans) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.92,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, controller) => Container(
          decoration: BoxDecoration(
            color: P.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: _SubagentsSheet(
            spans: spans,
            scrollController: controller,
          ),
        ),
      ),
    );
  }

  /// Assistant message copy without its tool calls, so the text renders
  /// as a normal message while the calls live in the Thoughts sheet.
  TranscriptItem _stripToolCalls(TranscriptItem t) => TranscriptItem(
        type: t.type,
        role: t.role,
        content: t.content,
        tsMs: t.tsMs,
      );

  /// The collapsed per-turn row: a quiet pill in the subagent-pill
  /// style with a real 44dp tap target. Tapping opens the Thoughts sheet.
  Widget _thoughtsRow(List<_ThoughtStep> steps, bool live) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openThoughts(steps, live),
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        margin: const EdgeInsets.only(bottom: 10, top: 2),
        alignment: Alignment.centerLeft,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: P.border),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.psychology_outlined,
                  size: 15, color: P.inkSecondary),
              const SizedBox(width: 8),
              Text('Thoughts',
                  style: PT.small.copyWith(color: P.inkSecondary)),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded,
                  size: 15, color: P.inkSecondary),
            ],
          ),
        ),
      ),
    );
  }

  void _openThoughts(List<_ThoughtStep> steps, bool live) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: P.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.92,
        child: _ThoughtsSheet(steps: steps, live: live),
      ),
    );
  }

  /// Elapsed-time clock for the live-turn row: anchored the first time
  /// a live status is observed, cleared when the turn settles.
  void _syncLiveClock(String status) {
    if (_isLive(status)) {
      _liveSinceMs ??= DateTime.now().millisecondsSinceEpoch;
      _liveTicker ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted && _isLive(_run?.status ?? '')) setState(() {});
      });
    } else {
      _liveSinceMs = null;
      _liveTicker?.cancel();
      _liveTicker = null;
    }
  }

  /// "Working for 1m 9s": quiet live-turn status row at the end of chat,
  /// ticking each second while the turn runs.
  Widget _workingRow() {
    final s =
        ((DateTime.now().millisecondsSinceEpoch - _liveSinceMs!) / 1000)
            .floor();
    final label = s >= 60
        ? 'Working for ${s ~/ 60}m ${s % 60}s'
        : 'Working for ${s}s';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 2),
      child: Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text(label, style: PT.small.copyWith(color: P.inkSecondary)),
        ],
      ),
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
              if (_attachedName != null) ...[
                _attachedChip(),
                const SizedBox(height: 8),
              ],
              if (_compressing) ...[
                _compressingRow(),
                const SizedBox(height: 8),
              ],
              if (_attachments.isNotEmpty) ...[
                _attachmentChips(),
                const SizedBox(height: 8),
              ],
              _modelPill(),
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

  /// Removable indicator chip above the composer naming the attached
  /// expert team or expert (set by "Use team" / "Use expert"). Tapping
  /// × dismisses the chip only — the session keeps running.
  Widget _attachedChip() {
    final name = _attachedName;
    if (name == null || name.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        Container(
          padding:
              const EdgeInsets.only(left: 12, top: 6, bottom: 6, right: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: P.accentSoft,
            border: Border.all(color: P.accent.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.attachedIcon,
                  size: 14, color: P.accent, weight: 1.8),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  name,
                  style: PT.label.copyWith(fontSize: 13, color: P.ink),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => setState(() => _attachedName = null),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: P.inkFaint.withValues(alpha: 0.25),
                  ),
                  child: Icon(Icons.close_rounded,
                      size: 12, color: P.inkSecondary),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Model pill above the composer: current `provider · model · effort`.
  /// Tapping opens the model picker (default slot + fallbacks from the
  /// `[model]` config, with a reasoning-effort selector); writes go
  /// through `PUT /api/config`.
  Widget _modelPill() {
    final label = _modelLine;
    if (label == null || label.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              _haptic(HapticFeedback.lightImpact);
              _modelPickerSheet();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                border: Border.all(color: P.border),
                borderRadius: BorderRadius.circular(999),
                color: P.tonal,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.smart_toy_outlined,
                      size: 14, color: P.inkSecondary),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      style: PT.small.copyWith(color: P.inkSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.expand_more_rounded,
                      size: 14, color: P.inkSecondary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Model picker sheet: the default `[model]` slot plus its fallback
  /// chain as tappable options, and a reasoning-effort selector. Both
  /// write through `PUT /api/config` and refresh the pill label.
  Future<void> _modelPickerSheet() async {
    ConfigDoc doc;
    try {
      doc = await widget.api.getConfig();
    } catch (e) {
      if (mounted) toastError(context, e);
      return;
    }
    final m = doc.values['model'];
    if (m is! Map || !mounted) return;
    var provider = m['provider']?.toString() ?? '';
    var model = m['model']?.toString() ?? '';
    var reasoning = (m['reasoning']?.toString() ?? 'off').toLowerCase();
    final options = <Map<String, String>>[
      {'provider': provider, 'model': model},
    ];
    final fb = m['fallbacks'];
    if (fb is List) {
      for (final f in fb) {
        if (f is Map) {
          options.add({
            'provider': f['provider']?.toString() ?? '',
            'model': f['model']?.toString() ?? '',
          });
        }
      }
    }
    const efforts = ['off', 'minimal', 'low', 'medium', 'high'];
    await showPSheet<void>(
      context,
      StatefulBuilder(
        builder: (context, setSheetState) {
          Future<void> applyModel(Map<String, String> opt) async {
            try {
              await widget.api.putConfig({
                'model.provider': opt['provider'] ?? '',
                'model.model': opt['model'] ?? '',
              });
            } catch (e) {
              if (mounted) toastError(context, e);
              return;
            }
            provider = opt['provider'] ?? '';
            model = opt['model'] ?? '';
            setSheetState(() {});
            if (mounted) {
              final line = await _safeModelLine();
              if (mounted) setState(() => _modelLine = line);
              toast(context, 'Model updated');
            }
          }

          Future<void> applyEffort(String level) async {
            try {
              await widget.api
                  .putConfig({'model.reasoning': level});
            } catch (e) {
              if (mounted) toastError(context, e);
              return;
            }
            setSheetState(() => reasoning = level);
            if (mounted) {
              final line = await _safeModelLine();
              if (mounted) setState(() => _modelLine = line);
            }
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SheetHandle(),
                  const SizedBox(height: 12),
                  Text('Model', style: PT.sectionTitle),
                  const SizedBox(height: 4),
                  Text('Default model for new turns.',
                      style: PT.small),
                  const SizedBox(height: 12),
                  for (final opt in options)
                    _modelOptionRow(
                      opt,
                      selected: opt['provider'] == provider &&
                          opt['model'] == model,
                      onTap: () => applyModel(opt),
                    ),
                  const SizedBox(height: 16),
                  Text('Reasoning effort', style: PT.rowTitle),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final e in efforts)
                        GestureDetector(
                          onTap: () {
                            _haptic(HapticFeedback.lightImpact);
                            applyEffort(e);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              color: reasoning == e
                                  ? P.accent
                                  : P.tonal,
                              border: Border.all(
                                  color: reasoning == e
                                      ? P.accent
                                      : P.border),
                            ),
                            child: Text(
                              e,
                              style: PT.small.copyWith(
                                  color: reasoning == e
                                      ? Colors.white
                                      : P.inkSecondary),
                            ),
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
  }

  Widget _modelOptionRow(Map<String, String> opt,
      {required bool selected, required VoidCallback onTap}) {
    final label = [
      if ((opt['provider'] ?? '').isNotEmpty) opt['provider'],
      if ((opt['model'] ?? '').isNotEmpty) opt['model'],
    ].join(' · ');
    return InkWell(
      onTap: () {
        _haptic(HapticFeedback.lightImpact);
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(label.isEmpty ? 'Unset' : label,
                  style: PT.body.copyWith(fontSize: 14)),
            ),
            if (selected)
              Icon(Icons.check_rounded, size: 18, color: P.accent),
          ],
        ),
      ),
    );
  }

  Widget _composerRow() {
    final returnSends = AppPreferences.instance.returnSends.value;
    final reduceMotion = AppPreferences.instance.reduceMotion.value;
    // Send/stop: while a turn is in flight (and we're not mid-send
    // ourselves) the button is a stop button in the Nyx danger wash —
    // tap stops at once, long-press opens the in-flight sheet.
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
          // Stop state: tap stops the turn at once; long-press opens
          // the full in-flight sheet (stop / steer / queue).
          onTap: stopLive ? _stopTurn : _send,
          onLongPress:
              stopLive ? () => _stopSheet() : null,
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

  /// Options bottom sheet (••• in the AppBar): only items wired to real
  /// functionality. Pin/Archive/Find-in-chat are intentionally absent —
  /// the backend exposes no pin or archive endpoints and the chat has
  /// no find UI — so they would be dead buttons.
  Future<void> _optionsSheet() async {
    final collapsed = _headerCollapsed;
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
              _optionRow(Icons.ios_share_rounded, 'Share',
                  () => Navigator.pop(context, 'share')),
              _optionRow(
                  collapsed
                      ? Icons.expand_more_rounded
                      : Icons.expand_less_rounded,
                  collapsed ? 'Expand header' : 'Collapse header',
                  () => Navigator.pop(context, 'collapse')),
              _optionRow(Icons.mic_rounded, 'Live mode',
                  () => Navigator.pop(context, 'live')),
              _optionRow(Icons.delete_outline_rounded, 'Delete',
                  () => Navigator.pop(context, 'delete'),
                  destructive: true),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case 'share':
        await _shareSession();
        break;
      case 'collapse':
        setState(() => _headerCollapsed = !_headerCollapsed);
        break;
      case 'live':
        _openVoice();
        break;
      case 'delete':
        await _deleteSession();
        break;
    }
  }

  Widget _optionRow(IconData icon, String label, VoidCallback onTap,
      {bool destructive = false}) {
    final color = destructive ? P.err : P.ink;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(P.r12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Row(
          children: [
            Icon(icon, size: 21, color: color, weight: 1.6),
            const SizedBox(width: 14),
            Text(label,
                style: PT.rowTitle.copyWith(fontSize: 15, color: color)),
          ],
        ),
      ),
    );
  }

  /// Share: export the transcript as markdown and open the system share
  /// sheet (the same path as `/export`).
  Future<void> _shareSession() async {
    try {
      final bytes = await widget.api.exportRun(widget.runId);
      if (!mounted) return;
      await showExportSheet(
          context, _run?.displayTitle ?? 'Session', bytes);
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  /// Delete this session after a confirm, then pop back to the list.
  Future<void> _deleteSession() async {
    final ok = await confirmAction(
      context,
      title: 'Delete session?',
      body:
          '“${_run?.displayTitle ?? 'This session'}” will be deleted. This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await widget.api.deleteRun(widget.runId);
      if (!mounted) return;
      Navigator.of(context).pop();
      toast(context, 'Deleted.');
    } catch (e) {
      if (mounted) toastError(context, e);
    }
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
                          ? Icon(Icons.open_in_new_rounded,
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
          if (a.size != null && a.size!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text('${_extLabel(a.name)} · ${a.size}',
                  style: PT.monoSm.copyWith(
                      color: P.inkSecondary, fontSize: 10),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center),
            ),
          ],
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
        // Assistant messages get copyable block cards (Writing/Code);
        // user text keeps the long-press copy menu.
        cards: !isUser && !isTool,
      );
      final body = <Widget>[msg];
      if (sentAtts.isNotEmpty) body.add(_sentAttachmentGrid(sentAtts));
      final header = Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: GestureDetector(
          onTap: _openAgentActivity,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ActiveProfileAvatar(api: widget.api, size: 22),
              const SizedBox(width: 8),
              // Assistant messages carry the agent/profile name, not a
              // generic "ASSISTANT" — resolved best-effort from config.
              Text(isTool ? 'TOOL' : _agentName,
                  style: PT.monoEyebrow
                      .copyWith(color: isTool ? P.info : P.accent)),
            ],
          ),
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
  /// Timeline tab: the shared [SessionTimeline] card (header, MAIN /
  /// SUBAGENT NN sections, expandable rows) inside the tab's scroll
  /// container. Retry of a failed turn stays wired here.
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
        child: SessionTimeline(
          run: run,
          retrying: _retrying,
          onRetry: _retryRun,
        ),
      ),
    );
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
                    Icon(Icons.psychology_outlined,
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
  /// Human size from the `[attachments]` block ("2.4 MB").
  final String? size;

  _SentAttachment(
      {required this.name, required this.mime, this.id, this.size});

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
          child: SizedBox(
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
      child: Icon(Icons.broken_image_outlined,
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

/// Tool-call status for the Thoughts sheet: spinner, check, or red X.
/// There is no pending state — a call with no result on a settled run
/// is an error, not a clock.
enum _StepStatus { running, done, error }

/// Tool name → step kind. Covers the contract kinds:
/// command | tool | delegate | file-search | web-search | read | edit.
String _stepKind(String name) {
  final n = name.toLowerCase();
  if (n.contains('delegate') ||
      n.contains('subagent') ||
      n.contains('dispatch') ||
      n.contains('swarm')) {
    return 'delegate';
  }
  if (n.contains('web') &&
      (n.contains('search') ||
          n.contains('lookup') ||
          n.contains('fetch') ||
          n.contains('crawl'))) {
    return 'web-search';
  }
  if (n.contains('grep') ||
      n.contains('glob') ||
      n.contains('find') ||
      n.contains('rg') ||
      n.contains('lookup')) {
    return 'file-search';
  }
  if (n.contains('search')) return 'web-search';
  if (n.contains('exec') ||
      n.contains('command') ||
      n.contains('shell') ||
      n.contains('bash') ||
      n.contains('terminal')) {
    return 'command';
  }
  if (n.contains('edit') ||
      n.contains('write') ||
      n.contains('patch') ||
      n.contains('apply')) {
    return 'edit';
  }
  if (n.contains('read')) return 'read';
  return 'tool';
}

/// MCP-ish names like `filesystem__read_file` → "Read File".
String _humanToolName(String name) {
  var n = name;
  final sep = n.lastIndexOf('__');
  if (sep >= 0) n = n.substring(sep + 2);
  final words = n
      .split(RegExp(r'[_\-\s]+'))
      .where((w) => w.isNotEmpty)
      .map((w) => '${w[0].toUpperCase()}${w.substring(1)}');
  final label = words.join(' ');
  return label.isEmpty ? name : label;
}

Map<String, dynamic>? _argsMap(String argsJson) {
  try {
    final v = jsonDecode(argsJson);
    if (v is Map) return v.cast<String, dynamic>();
  } catch (_) {}
  return null;
}

String? _nonEmptyArg(dynamic v) =>
    v is String && v.trim().isNotEmpty ? v.trim() : null;

/// Delegate call extras parsed from the call arguments. Key names vary
/// across backends, so probe the common ones.
String? _delegateAgent(Map<String, dynamic> args) =>
    _nonEmptyArg(args['agent']) ??
    _nonEmptyArg(args['subagent_type']) ??
    _nonEmptyArg(args['subagent']) ??
    _nonEmptyArg(args['name']);

String? _delegateTask(Map<String, dynamic> args) =>
    _nonEmptyArg(args['task']) ??
    _nonEmptyArg(args['description']) ??
    _nonEmptyArg(args['summary']) ??
    _nonEmptyArg(args['title']);

String? _delegatePrompt(Map<String, dynamic> args) =>
    _nonEmptyArg(args['prompt']) ??
    _nonEmptyArg(args['message']) ??
    _nonEmptyArg(args['instructions']) ??
    _nonEmptyArg(args['input']);

/// One row in the Thoughts sheet / agent sheet: a reasoning summary or
/// a tool call with its result, derived from the new transcript
/// contract (ts_ms, tool_calls[{id,name,arguments,started_ms,
/// duration_ms}], tool_call_id, duration_ms on tool results).
class _ThoughtStep {
  final bool isReasoning;
  final String? reasoningText;
  final ToolCallRef? call;
  final TranscriptItem? result;
  final _StepStatus status;

  /// Step identity and derived presentation.
  final String id;
  final String kind;
  final String label;
  final String args;
  final String output;
  final int? startedAtMs;
  final int? durationMs;

  /// Delegate extras: agent, task, prompt; the agent's result is [output].
  final String? agent;
  final String? task;
  final String? prompt;

  /// Transcript index of the assistant item that owns this step — the
  /// subagent pill anchors here, never on a timestamp scan.
  final int transcriptIndex;

  bool get isDelegate => kind == 'delegate';

  _ThoughtStep.reasoning(this.reasoningText, [this.transcriptIndex = -1])
      : isReasoning = true,
        call = null,
        result = null,
        status = _StepStatus.done,
        id = '',
        kind = 'reasoning',
        label = '',
        args = '',
        output = '',
        startedAtMs = null,
        durationMs = null,
        agent = null,
        task = null,
        prompt = null;

  _ThoughtStep.tool({
    required ToolCallRef call,
    TranscriptItem? result,
    required this.transcriptIndex,
    required bool live,
    int? ownerTsMs,
  })  : isReasoning = false,
        reasoningText = null,
        call = call,
        result = result,
        id = call.id,
        kind = _stepKind(call.name),
        startedAtMs = call.startedMs,
        durationMs = _resolveDuration(call, result, ownerTsMs),
        args = _prettyArgs(call.arguments),
        output = result?.content ?? '',
        status = result != null
            ? (_looksLikeError(result.content)
                ? _StepStatus.error
                : _StepStatus.done)
            : (live ? _StepStatus.running : _StepStatus.error),
        agent = _stepKind(call.name) == 'delegate'
            ? _delegateAgent(_argsMap(call.arguments) ?? const {})
            : null,
        task = _stepKind(call.name) == 'delegate'
            ? _delegateTask(_argsMap(call.arguments) ?? const {})
            : null,
        prompt = _stepKind(call.name) == 'delegate'
            ? _delegatePrompt(_argsMap(call.arguments) ?? const {})
            : null,
        label = _stepLabel(call, result, live);

  /// A tool result row with no matching call row: shown as a step with
  /// its output, never as a fake assistant message.
  _ThoughtStep.orphanResult(TranscriptItem res, [this.transcriptIndex = -1])
      : isReasoning = false,
        reasoningText = null,
        call = null,
        result = res,
        status = _StepStatus.done,
        id = res.toolCallId ?? '',
        kind = 'tool',
        label = 'Tool result',
        args = '',
        output = res.content,
        startedAtMs = null,
        durationMs = res.durationMs,
        agent = null,
        task = null,
        prompt = null;

  /// Backend duration_ms wins (on the call, then on the result row);
  /// otherwise fall back to the owner→result timestamp delta.
  static int? _resolveDuration(
      ToolCallRef call, TranscriptItem? result, int? ownerTsMs) {
    final direct = call.durationMs ?? result?.durationMs;
    if (direct != null && direct >= 0) return direct;
    if (result?.tsMs != null && ownerTsMs != null) {
      final ms = result!.tsMs! - ownerTsMs;
      if (ms >= 0) return ms;
    }
    return null;
  }

  /// Self-describing collapsed label, running vs past tense. Delegates
  /// read "Delegate → {agent}: {task}".
  static String _stepLabel(
      ToolCallRef call, TranscriptItem? result, bool live) {
    final kind = _stepKind(call.name);
    if (kind == 'delegate') {
      final m = _argsMap(call.arguments) ?? const {};
      final a = _delegateAgent(m) ?? 'agent';
      final t = _delegateTask(m) ?? _humanToolName(call.name);
      return 'Delegate \u2192 $a: $t';
    }
    final past = result != null || !live;
    final human = _humanToolName(call.name);
    return switch (kind) {
      'command' => past ? 'Ran command' : 'Running command',
      'file-search' => past ? 'Searched files' : 'Searching files',
      'web-search' => past ? 'Searched the web' : 'Searching the web',
      'read' => past ? 'Read file' : 'Reading file',
      'edit' => past ? 'Edited file' : 'Editing file',
      _ => past ? 'Ran $human' : 'Running $human',
    };
  }
}

/// Best-effort error detection: the backend has no machine-readable
/// error marker on tool results, so match the common "Error…" prefix.
bool _looksLikeError(String content) =>
    content.trimLeft().toLowerCase().startsWith('error');

String _trunc(String s, int n) =>
    s.length <= n ? s : '${s.substring(0, n).trimRight()}…';

String _prettyArgs(String argsJson) {
  try {
    return const JsonEncoder.withIndent('  ').convert(jsonDecode(argsJson));
  } catch (_) {
    return argsJson;
  }
}

/// "1.1s" / "350ms" from a step's resolved duration.
String? _stepDuration(_ThoughtStep s) {
  final ms = s.durationMs;
  if (ms == null || ms < 0) return null;
  if (ms < 1000) return '${ms}ms';
  return '${(ms / 1000).toStringAsFixed(1)}s';
}

String _reasoningSummary(String text) {
  final first = text.trim().split('\n').first.trim();
  return _trunc(first, 64);
}

/// Checklist row title: the step's self-describing label
/// ("Running command", "Delegate → researcher: …"), or the reasoning
/// summary for reasoning steps.
String _stepTitle(_ThoughtStep s) {
  if (s.isReasoning) return _reasoningSummary(s.reasoningText ?? '');
  return s.label;
}

/// Verb label for an expanded tool card: the same self-describing label.
String _detailVerb(_ThoughtStep s) {
  if (s.isReasoning) return 'Reasoning';
  return s.label;
}

final _urlRe = RegExp(r'https?://[^\s)>\]]+');

/// Domains referenced by a search-type tool's result, for the sources
/// rows (favicon + domain label).
List<String> _sourceDomains(String resultText) {
  final seen = <String>[];
  for (final m in _urlRe.allMatches(resultText)) {
    final host = Uri.tryParse(m.group(0)!)?.host ?? '';
    final h = host.startsWith('www.') ? host.substring(4) : host;
    if (h.isNotEmpty && !seen.contains(h)) seen.add(h);
  }
  return seen;
}

/// Near-full-screen "Thoughts" sheet: a vertical checklist of one
/// turn's steps — reasoning summaries and tool calls — each with a
/// status glyph and a chevron. Tapping a row expands its detail card.
/// Quiet and monochrome: no chat-bubble styling, no ASSISTANT label.
class _ThoughtsSheet extends StatefulWidget {
  final List<_ThoughtStep> steps;

  /// Whether the turn that produced these steps is still live. A
  /// finished, non-live turn gets a trailing "Done" row.
  final bool live;

  const _ThoughtsSheet({required this.steps, required this.live});

  @override
  State<_ThoughtsSheet> createState() => _ThoughtsSheetState();
}

class _ThoughtsSheetState extends State<_ThoughtsSheet> {
  final Set<int> _open = {};

  /// Rows whose output is expanded to the full selectable text.
  final Set<int> _fullOutput = {};

  /// Output preview length before the tap-to-expand cutoff.
  static const _outputPreview = 500;

  /// "Done" row: the turn finished and isn't live.
  bool get _showDone => !widget.live && widget.steps.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          const Center(child: SheetHandle()),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 12, 12),
            child: Row(
              children: [
                Text('Thoughts', style: PT.sectionTitle),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: P.inkSecondary),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: widget.steps.length + (_showDone ? 1 : 0),
              itemBuilder: (_, i) => i < widget.steps.length
                  ? _stepRow(widget.steps[i], i)
                  : _doneRow(),
            ),
          ),
        ],
      ),
    );
  }

  /// Final "Done" row when the turn finished and isn't live.
  Widget _doneRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          child: Row(
            children: [
              _statusGlyph(_StepStatus.done),
              const SizedBox(width: 12),
              Text('Done', style: PT.body.copyWith(fontSize: 14)),
            ],
          ),
        ),
        const Divider(height: 1, indent: 20, endIndent: 20),
      ],
    );
  }

  Widget _stepRow(_ThoughtStep s, int index) {
    final open = _open.contains(index);
    final dur = _stepDuration(s);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(
              () => open ? _open.remove(index) : _open.add(index)),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
            child: Row(
              children: [
                _statusGlyph(s.status),
                const SizedBox(width: 12),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      text: _stepTitle(s),
                      style: PT.body.copyWith(fontSize: 14),
                      children: [
                        if (dur != null)
                          TextSpan(
                              text: ' \u00b7 $dur',
                              style: PT.faint.copyWith(fontSize: 12)),
                      ],
                    ),
                  ),
                ),
                Icon(
                    open
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 18,
                    color: P.inkSecondary),
              ],
            ),
          ),
        ),
        if (open) _stepDetail(s, index),
        const Divider(height: 1, indent: 20, endIndent: 20),
      ],
    );
  }

  /// Status glyph: spinner (running), check (done), red X (error).
  /// There is intentionally no pending/clock state.
  Widget _statusGlyph(_StepStatus status) {
    switch (status) {
      case _StepStatus.running:
        return const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case _StepStatus.done:
        return Icon(Icons.check_rounded,
            size: 16, color: P.inkSecondary);
      case _StepStatus.error:
        return const Icon(Icons.close_rounded, size: 16, color: P.err);
    }
  }

  Widget _detailCard({required Widget child}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: P.tonal,
        borderRadius: BorderRadius.circular(P.r12),
        border: Border.all(color: P.border),
      ),
      child: child,
    );
  }

  Widget _stepDetail(_ThoughtStep s, int index) {
    if (s.isReasoning) {
      return _detailCard(
        child: SelectableText(
          s.reasoningText ?? '',
          style: PT.body.copyWith(fontSize: 13, color: P.inkSecondary),
        ),
      );
    }
    if (s.isDelegate) return _delegateDetail(s);
    return _toolDetail(s, index);
  }

  /// Delegate expansion stays minimal: the agent sheet owns the prompt,
  /// the result, and the nested steps — this row only identifies the
  /// delegation so the two never duplicate each other.
  Widget _delegateDetail(_ThoughtStep s) {
    final dur = _stepDuration(s);
    return _detailCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_detailVerb(s),
              style: PT.monoEyebrow.copyWith(color: P.inkSecondary)),
          const SizedBox(height: 8),
          if (s.agent != null) _delegateLine('Agent', s.agent!),
          if (s.task != null) _delegateLine('Task', s.task!),
          if (dur != null) ...[
            const SizedBox(height: 6),
            Text('\u00b7 $dur', style: PT.faint),
          ],
          const SizedBox(height: 6),
          Text('Full prompt and result live in the agent view.',
              style: PT.meta),
        ],
      ),
    );
  }

  Widget _delegateLine(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 52,
            child: Text(k,
                style: PT.monoEyebrow.copyWith(fontSize: 10)),
          ),
          Expanded(
            child: SelectableText(v, style: PT.small),
          ),
        ],
      ),
    );
  }

  Widget _toolDetail(_ThoughtStep s, int index) {
    final dur = _stepDuration(s);
    final sources = s.result != null &&
            (s.kind == 'web-search' || s.kind == 'file-search')
        ? _sourceDomains(s.output)
        : const <String>[];
    final resultText = s.output;
    final showFull = _fullOutput.contains(index);
    final truncated = resultText.length > _outputPreview;
    final shown = !truncated || showFull
        ? resultText
        : '${resultText.substring(0, _outputPreview).trimRight()}\u2026';
    return _detailCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(_detailVerb(s),
                    style:
                        PT.monoEyebrow.copyWith(color: P.inkSecondary)),
              ),
              if (s.args.trim().isNotEmpty)
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: s.args));
                    toast(context, 'Arguments copied.');
                    HapticFeedback.lightImpact();
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(Icons.copy_rounded,
                        size: 15, color: P.inkSecondary),
                  ),
                ),
            ],
          ),
          if (s.args.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            _argsCard(s.args),
          ],
          if (dur != null) ...[
            const SizedBox(height: 6),
            Text('\u00b7 $dur', style: PT.faint),
          ],
          if (sources.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('SOURCES',
                style: PT.monoEyebrow.copyWith(color: P.inkSecondary)),
            const SizedBox(height: 6),
            for (final d in sources) _sourceRow(d),
          ],
          if (resultText.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
                s.status == _StepStatus.error ? 'ERROR' : 'RESULT',
                style: PT.monoEyebrow.copyWith(
                    color: s.status == _StepStatus.error
                        ? P.err
                        : P.inkSecondary)),
            const SizedBox(height: 6),
            SelectableText(
              shown,
              style: PT.monoSm.copyWith(color: P.inkSecondary),
            ),
            if (truncated)
              GestureDetector(
                onTap: () => setState(() => showFull
                    ? _fullOutput.remove(index)
                    : _fullOutput.add(index)),
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(showFull ? 'Show less' : 'Show more',
                      style: PT.small.copyWith(color: P.accent)),
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// Command/args on a dark monospace code card. The header copy button
  /// copies the FULL arguments, never the summary.
  Widget _argsCard(String args) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(P.r8),
        border: Border.all(color: P.border),
      ),
      child: SelectableText(
        args,
        style: const TextStyle(
          fontFamily: 'JetBrainsMono',
          fontSize: 12,
          height: 1.5,
          color: Color(0xFFE8E8E8),
        ),
      ),
    );
  }

  Widget _sourceRow(String domain) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Image.network(
            'https://www.google.com/s2/favicons?domain=$domain&sz=32',
            width: 16,
            height: 16,
            errorBuilder: (_, __, ___) => Icon(Icons.public_rounded,
                size: 16, color: P.inkSecondary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(domain,
                style: PT.small.copyWith(color: P.inkSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

/// One subagent's activity span: a maximal run of agent-kind timeline
/// events (`agent_spawned` → `agent_message`* → `agent_completed`).
/// The backend does not expose subagent transcripts, so the span's
/// nested content is its timeline events — the same data source the
/// agent activity view uses.
class _SubagentSpan {
  final String name;
  final int? startedMs;
  final int? endedMs;
  final List<TimelineItem> items;

  const _SubagentSpan({
    required this.name,
    required this.startedMs,
    required this.endedMs,
    required this.items,
  });

  bool get completed => endedMs != null;

  /// Elapsed wall time: spawn → completion, or spawn → now while
  /// still running.
  Duration get elapsed {
    final start = startedMs ?? DateTime.now().millisecondsSinceEpoch;
    final end =
        endedMs ?? DateTime.now().millisecondsSinceEpoch;
    return Duration(milliseconds: (end - start).clamp(0, 1 << 62));
  }

  String get statusLabel {
    final e = elapsed;
    final t = e.inMinutes > 0
        ? '${e.inMinutes}m ${e.inSeconds % 60}s'
        : '${e.inSeconds}s';
    return completed ? 'Completed · $t' : 'Running · $t';
  }
}

/// Near-full-screen sheet listing the turn's subagents: task name,
/// status with elapsed time, and each subagent's nested content — its
/// timeline events as checklist rows in the same visual language as
/// the Thoughts sheet.
class _SubagentsSheet extends StatefulWidget {
  final List<_SubagentSpan> spans;
  final ScrollController scrollController;

  const _SubagentsSheet(
      {required this.spans, required this.scrollController});

  @override
  State<_SubagentsSheet> createState() => _SubagentsSheetState();
}

class _SubagentsSheetState extends State<_SubagentsSheet> {
  final Set<int> _open = {};

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          const Center(child: SheetHandle()),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 12, 12),
            child: Row(
              children: [
                Text('Subagents', style: PT.sectionTitle),
                const Spacer(),
                IconButton(
                  icon:
                      Icon(Icons.close_rounded, color: P.inkSecondary),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              controller: widget.scrollController,
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: widget.spans.length,
              itemBuilder: (_, i) => _agentBlock(widget.spans[i], i),
            ),
          ),
        ],
      ),
    );
  }

  Widget _agentBlock(_SubagentSpan span, int index) {
    final open = _open.contains(index);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () =>
              setState(() => open ? _open.remove(index) : _open.add(index)),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
            child: Row(
              children: [
                _agentStatusGlyph(span),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(span.name,
                          style: PT.body.copyWith(
                              fontSize: 14,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(span.statusLabel, style: PT.meta),
                    ],
                  ),
                ),
                Icon(
                    open
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 18,
                    color: P.inkSecondary),
              ],
            ),
          ),
        ),
        if (open)
          ...span.items.map((e) => _eventRow(e)),
        const Divider(height: 1, indent: 20, endIndent: 20),
      ],
    );
  }

  Widget _agentStatusGlyph(_SubagentSpan span) {
    if (span.completed) {
      return Icon(Icons.check_rounded, size: 16, color: P.inkSecondary);
    }
    return const SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }

  /// One timeline event in the subagent's nested content: status glyph
  /// plus title, with detail on a second line.
  Widget _eventRow(TimelineItem e) {
    final spec = tlGlyph(e.kind);
    final detail = (e.detail ?? '').trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(52, 4, 20, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GlyphCircle(icon: spec.icon, color: spec.color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tlTitle(e.kind),
                    style: PT.body.copyWith(
                        fontSize: 13.5, fontWeight: FontWeight.w600)),
                if (detail.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(detail, style: PT.meta),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
