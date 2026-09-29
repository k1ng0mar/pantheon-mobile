import 'package:flutter/material.dart';

import '../models/pantheon_run.dart';
import '../services/pantheon_api.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/chips.dart';
import '../widgets/export_sheet.dart';
import '../widgets/forms.dart';
import '../widgets/states.dart';
import 'session_detail_screen.dart';

/// Sessions: one row per conversation, Muse-style — title, last activity,
/// time, grouped by day. A session's runs (turns, tool calls, timeline)
/// live inside the detail view.
class SessionsScreen extends StatefulWidget {
  final PantheonApi api;

  const SessionsScreen({super.key, required this.api});

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  final _search = TextEditingController();
  String? _statusFilter;
  Future<List<PantheonRun>>? _future;

  static const _statuses = [
    'running',
    'awaiting_approval',
    'completed',
    'failed',
    'canceled',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _load() {
    setState(() {
      _future = widget.api.runs(
        q: _search.text.trim().isEmpty ? null : _search.text.trim(),
        status: _statusFilter,
      );
    });
  }

  /// Start a new chat: ask for the opening message (+ optional title),
  /// create the run, and drop straight into it.
  Future<void> _newChat() async {
    final messageCtrl = TextEditingController();
    final titleCtrl = TextEditingController();
    bool busy = false;
    try {
      final created = await showPSheet<PantheonRun>(
        context,
        StatefulBuilder(
          builder: (ctx, setSheet) => SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  20, 8, 20, 24 + MediaQuery.of(ctx).viewInsets.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SheetHandle(),
                  const SizedBox(height: 8),
                   Text('New chat', style: PT.sectionTitle),
                  const SizedBox(height: 4),
                   Text('Your first message starts the session.',
                      style: PT.meta),
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
                  if (busy)
                     SizedBox(
                      height: 52,
                      child: Center(
                          child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.5, color: P.accent))),
                    )
                  else
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
                            label: 'Start',
                            onTap: () async {
                              final msg = messageCtrl.text.trim();
                              if (msg.isEmpty) return;
                              setSheet(() => busy = true);
                              try {
                                final run = await widget.api.createRun(
                                  message: msg,
                                  title: titleCtrl.text.trim().isEmpty
                                      ? null
                                      : titleCtrl.text.trim(),
                                );
                                if (ctx.mounted) Navigator.pop(ctx, run);
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
          ),
        ),
      );
      if (created != null && mounted) {
        _load();
        Navigator.of(context).push(_detailRoute(created));
      }
    } finally {
      messageCtrl.dispose();
      titleCtrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sessions'),
        actions: [
          IconButton(
            icon:  Icon(Icons.refresh_rounded,
                color: P.inkSecondary, weight: 1.6),
            onPressed: _load,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newChat,
        backgroundColor: P.accentDeep,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded, weight: 2),
        label: const Text('New chat',
            style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _load(),
              onChanged: (_) => setState(() {}),
              style: PT.body,
              decoration: InputDecoration(
                hintText: 'Search sessions…',
                prefixIcon:  Icon(Icons.search_rounded,
                    color: P.inkFaint, weight: 1.6),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon:  Icon(Icons.clear_rounded,
                            color: P.inkFaint),
                        onPressed: () {
                          _search.clear();
                          _load();
                        },
                      ),
              ),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                _filterChip(null, 'all'),
                for (final s in _statuses)
                  _filterChip(s, s.replaceAll('_', ' ')),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<PantheonRun>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return _skeleton();
                }
                if (snap.hasError) {
                  return EmptyState(
                    icon: Icons.cloud_off_outlined,
                    title: 'Couldn\'t load sessions',
                    body: snap.error.toString(),
                    ctaLabel: 'Retry',
                    onCta: _load,
                  );
                }
                final sessions = snap.data!;
                if (sessions.isEmpty) {
                  return const EmptyState(
                    icon: Icons.forum_outlined,
                    title: 'No sessions yet',
                    body: 'Start a conversation in the TUI and it will show up here.',
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => _load(),
                  color: P.accent,
                  backgroundColor: P.surface,
                  child: _groupedList(sessions),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String? value, String label) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: PillChip(
        label: label,
        selected: _statusFilter == value,
        onTap: () {
          setState(() => _statusFilter = value);
          _load();
        },
      ),
    );
  }

  /// Newest activity first, grouped under day headers.
  Widget _groupedList(List<PantheonRun> sessions) {
    final sorted = sessions.toList()
      ..sort((a, b) => _recency(b).compareTo(_recency(a)));
    final items = <Widget>[];
    String? lastDay;
    var index = 0;
    for (final s in sorted) {
      final day = _dayLabel(_recency(s));
      if (day != lastDay) {
        lastDay = day;
        items.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Text(day, style: PT.sectionTitle),
        ));
      }
      items.add(StaggerItem(index: index++, child: _sessionRow(s)));
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
      children: items,
    );
  }

  static int _recency(PantheonRun s) =>
      s.updatedMs > 0 ? s.updatedMs : s.createdMs;

  Widget _sessionRow(PantheonRun s) {
    final live = s.status == 'running';
    final subtitle = (s.lastActivity?.isNotEmpty ?? false)
        ? s.lastActivity!
        : '${s.turns} turns · ${s.toolCalls} tool calls';
    return InkWell(
      onTap: () => Navigator.of(context).push(_detailRoute(s)),
      onLongPress: () => _sessionActions(s),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Stack(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: P.accentSoft,
                    border: Border.all(color: P.borderStrong),
                  ),
                  child:  Icon(Icons.hub_outlined,
                      color: P.accent, size: 26, weight: 1.6),
                ),
                if (live)
                  const Positioned(
                    right: 2,
                    bottom: 2,
                    child: LiveDot(size: 10),
                  ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.displayTitle,
                    style: PT.rowTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: PT.meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _timeLabel(_recency(s)),
                    style: PT.meta.copyWith(color: P.inkFaint),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Long-press actions on a session row: rename, export, fork, delete.
  Future<void> _sessionActions(PantheonRun s) async {
    final action = await showPSheet<String>(
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
              Text(s.displayTitle,
                  style: PT.rowTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 12),
              _actionRow(Icons.edit_outlined, 'Rename',
                  () => Navigator.pop(context, 'rename')),
              _actionRow(Icons.ios_share_rounded, 'Export transcript',
                  () => Navigator.pop(context, 'export')),
              _actionRow(Icons.call_split_rounded, 'Fork session',
                  () => Navigator.pop(context, 'fork')),
              _actionRow(Icons.delete_outline_rounded, 'Delete',
                  () => Navigator.pop(context, 'delete'),
                  destructive: true),
            ],
          ),
        ),
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'rename':
        final title = await promptText(context,
            title: 'Rename session', initial: s.title);
        if (title == null || title.isEmpty || !mounted) return;
        try {
          await widget.api.renameRun(s.id, title);
          toast(context, 'Renamed.');
          await _load();
        } catch (e) {
          if (mounted) toastError(context, e);
        }
        break;
      case 'export':
        try {
          final bytes = await widget.api.exportRun(s.id);
          if (!mounted) return;
          await showExportSheet(context, s.displayTitle, bytes);
        } catch (e) {
          if (mounted) toastError(context, e);
        }
        break;
      case 'fork':
        try {
          final forked = await widget.api.forkRun(s.id);
          if (!mounted) return;
          toast(context, 'Forked.');
          await Navigator.of(context).push(_detailRoute(forked));
          await _load();
        } catch (e) {
          if (mounted) toastError(context, e);
        }
        break;
      case 'delete':
        final ok = await confirmAction(
          context,
          title: 'Delete session?',
          body: '“${s.displayTitle}” will be deleted. This cannot be undone.',
          confirmLabel: 'Delete',
          destructive: true,
        );
        if (ok && mounted) {
          try {
            await widget.api.deleteRun(s.id);
            toast(context, 'Deleted.');
            await _load();
          } catch (e) {
            if (mounted) toastError(context, e);
          }
        }
        break;
    }
  }

  Widget _actionRow(IconData icon, String label, VoidCallback onTap,
      {bool destructive = false}) {
    final color = destructive ? P.err : P.ink;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(P.r12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 14),
            Text(label,
                style: PT.rowTitle.copyWith(
                    fontSize: 15, color: color)),
          ],
        ),
      ),
    );
  }

  Route _detailRoute(PantheonRun s) {
    return PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) =>
          SessionDetailScreen(api: widget.api, runId: s.id),
      transitionsBuilder: (_, anim, __, child) {
        final slide = Tween<Offset>(
                begin: const Offset(0.08, 0), end: Offset.zero)
            .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic));
        final fade = Tween<double>(begin: 0, end: 1)
            .animate(CurvedAnimation(parent: anim, curve: Curves.easeOut));
        return SlideTransition(
            position: slide,
            child: FadeTransition(opacity: fade, child: child));
      },
    );
  }

  Widget _skeleton() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: 6,
      itemBuilder: (_, __) => const Padding(
        padding: EdgeInsets.only(bottom: 10),
        child: Shimmer(width: double.infinity, height: 72, radius: 16),
      ),
    );
  }
}

String _dayLabel(int tsMs) {
  final now = DateTime.now();
  final d = DateTime.fromMillisecondsSinceEpoch(tsMs);
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  final m = months[d.month - 1];
  return d.year == now.year ? '$m ${d.day}' : '$m ${d.day}, ${d.year}';
}

String _timeLabel(int tsMs) {
  final d = DateTime.fromMillisecondsSinceEpoch(tsMs);
  var h = d.hour % 12;
  if (h == 0) h = 12;
  final mm = d.minute.toString().padLeft(2, '0');
  final ap = d.hour < 12 ? 'am' : 'pm';
  return '$h:$mm$ap';
}
