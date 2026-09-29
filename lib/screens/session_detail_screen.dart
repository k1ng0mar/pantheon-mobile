import 'dart:async';

import 'package:flutter/material.dart';

import '../models/pantheon_run.dart';
import '../services/pantheon_api.dart';
import '../theme.dart';
import '../widgets/chips.dart';
import '../widgets/forms.dart';
import '../widgets/states.dart';

/// A session as a real chat: transcript bubbles, live polling while the
/// run is active, and a composer that sends into the run via
/// `POST /api/runs/:id/message`. Settled sessions keep their composer:
/// completed/failed/canceled only end the latest turn — the runtime
/// reopens the run when a new message arrives.
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
  String? _error;
  bool _loading = true;

  final _composer = TextEditingController();
  final _scroll = ScrollController();
  Timer? _poll;
  bool _sending = false;
  bool _atBottom = true;

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
      setState(() {
        _run = run;
        _messages
          ..clear()
          ..addAll(run.transcript);
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

  void _syncPolling(String status) {
    final live = _isLive(status);
    if (live && _poll == null) {
      _poll = Timer.periodic(const Duration(seconds: 3), (_) => _pollOnce());
    } else if (!active) {
      _poll?.cancel();
      _poll = null;
    }
  }

  /// Fetch the latest detail and merge any new transcript items.
  Future<void> _pollOnce() async {
    if (!mounted) return;
    try {
      final run = await widget.api.runDetail(widget.runId);
      if (!mounted) return;
      final fresh = run.transcript;
      var added = false;
      if (fresh.length > _messages.length) {
        setState(() {
          _messages.addAll(fresh.sublist(_messages.length));
          added = true;
        });
      }
      if (run.status != _run?.status) {
        setState(() => _run = run);
      } else {
        _run = run;
      }
      _syncPolling(run.status);
      if (added && _atBottom) _animateToBottom();
    } catch (_) {
      // Polling is best-effort; the next tick retries.
    }
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty || _sending) return;
    final run = _run;
    if (run == null || !_canChat(run.status)) return;
    setState(() => _sending = true);
    _composer.clear();
    final optimistic =
        TranscriptItem(type: 'message', role: 'user', content: text);
    setState(() => _messages.add(optimistic));
    _animateToBottom();
    try {
      await widget.api.sendRunMessage(run.id, text);
      // Pull the authoritative transcript right away, and make sure the
      // poller is running: a settled session just reopened, so replies
      // stream in from here.
      _poll ??=
          Timer.periodic(const Duration(seconds: 3), (_) => _pollOnce());
      await _pollOnce();
    } on PantheonRunFinishedException {
      if (!mounted) return;
      setState(() => _messages.remove(optimistic));
      await _load();
      toast(context, 'This session could not be reopened.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _messages.remove(optimistic));
      toastError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
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
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.chevron_left_rounded,
              size: 30, color: P.ink, weight: 1.6),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(title),
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
              StatusChip(
                label: run.status.replaceAll('_', ' ').toUpperCase(),
                color: _statusColor(run.status),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${timeAgo(run.createdMs)}${run.model != null ? ' · ${run.model}' : ''}${run.provider != null ? ' (${run.provider})' : ''}',
            style: PT.small.copyWith(color: const Color(0xFFB9AEE0)),
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

  Widget _chatTab() {
    return Column(
      children: [
        Expanded(child: _messageList()),
        _composerBar(),
      ],
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
              hintText: 'Message Pantheon…',
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
