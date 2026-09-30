import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/pantheon_api.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/chips.dart';
import '../widgets/forms.dart';
import '../widgets/pantheon_card.dart';
import '../widgets/states.dart';

/// Tools & MCP: server groups, enable/disable, test, add, delete, reload.
class McpScreen extends StatefulWidget {
  final PantheonApi api;

  const McpScreen({super.key, required this.api});

  @override
  State<McpScreen> createState() => _McpScreenState();
}

class _McpScreenState extends State<McpScreen> {
  Future<({List<McpServerGroup> groups, List<String> pending, String? note})>?
      _future;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() => _future = widget.api.mcpServers());
  }

  Future<void> _toggle(McpServer s) async {
    setState(() => _busy.add(s.name));
    try {
      await widget.api.setMcpServerEnabled(s.name, !s.enabled);
      if (!mounted) return;
      toast(context, '“${s.name}” ${s.enabled ? 'disabled' : 'enabled'}.');
      _load();
    } catch (e) {
      if (mounted) toastError(context, e);
    } finally {
      if (mounted) setState(() => _busy.remove(s.name));
    }
  }

  Future<void> _test(McpServer s) async {
    setState(() => _busy.add(s.name));
    try {
      final res = await widget.api.testMcpServer(s.name);
      if (!mounted) return;
      final ok = res['ok'] == true;
      toast(context, ok ? '“${s.name}” reachable.' : 'Test: ${res['error'] ?? res}');
    } catch (e) {
      if (mounted) toastError(context, e);
    } finally {
      if (mounted) setState(() => _busy.remove(s.name));
    }
  }

  Future<void> _delete(McpServer s) async {
    final ok = await confirmAction(
      context,
      title: 'Delete server?',
      body: '“${s.name}” will be removed from its declaration file.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await widget.api.deleteMcpServer(s.name);
      if (!mounted) return;
      toast(context, 'Server deleted.');
      _load();
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  Future<void> _reload() async {
    try {
      await widget.api.reloadMcp();
      if (!mounted) return;
      toast(context, 'MCP reloaded.');
      _load();
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  Future<void> _approve(String name) async {
    setState(() => _busy.add(name));
    try {
      await widget.api.approveMcpServer(name);
      if (!mounted) return;
      toast(context, '“$name” approved.');
      _load();
    } catch (e) {
      if (mounted) toastError(context, e);
    } finally {
      if (mounted) setState(() => _busy.remove(name));
    }
  }

  Future<void> _add() async {
    final nameCtrl = TextEditingController();
    final cmdCtrl = TextEditingController();
    final argsCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    String transport = 'stdio';
    try {
      final created = await showPSheet<bool>(
        context,
        StatefulBuilder(
          builder: (ctx, setSheet) => SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                  20, 8, 20, 24 + MediaQuery.of(ctx).viewInsets.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SheetHandle(),
                  const SizedBox(height: 8),
                   Text('Add MCP server', style: PT.sectionTitle),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameCtrl,
                    style: PT.mono.copyWith(color: P.ink),
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      hintText: 'e.g. filesystem',
                    ),
                  ),
                  const SizedBox(height: 12),
                   Text('TRANSPORT', style: PT.overline),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (final t in ['stdio', 'http', 'sse'])
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: PillChip(
                              label: t,
                              selected: transport == t,
                              onTap: () =>
                                  setSheet(() => transport = t),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (transport == 'stdio') ...[
                    TextField(
                      controller: cmdCtrl,
                      style: PT.mono.copyWith(color: P.ink),
                      decoration: const InputDecoration(
                        labelText: 'Command',
                        hintText: 'e.g. npx',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: argsCtrl,
                      style: PT.mono.copyWith(color: P.ink),
                      decoration: const InputDecoration(
                        labelText: 'Args (space-separated, optional)',
                        hintText: '-y @modelcontextprotocol/server-fs',
                      ),
                    ),
                  ] else ...[
                    TextField(
                      controller: urlCtrl,
                      style: PT.mono.copyWith(color: P.ink),
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                        labelText: 'URL',
                        hintText: 'https://…',
                      ),
                    ),
                  ],
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
                          label: 'Add',
                          onTap: () async {
                            final name = nameCtrl.text.trim();
                            if (name.isEmpty) {
                              toast(ctx, 'Name is required.');
                              return;
                            }
                            final server = <String, dynamic>{
                              'name': name,
                              'transport': transport,
                              if (transport == 'stdio') ...{
                                'command': cmdCtrl.text.trim(),
                                if (argsCtrl.text.trim().isNotEmpty)
                                  'args': argsCtrl.text
                                      .trim()
                                      .split(RegExp(r'\s+')),
                              } else
                                'url': urlCtrl.text.trim(),
                            };
                            try {
                              await widget.api.addMcpServer(server);
                              if (ctx.mounted) Navigator.pop(ctx, true);
                            } catch (e) {
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
          ),
        ),
      );
      if (created == true && mounted) {
        toast(context, 'Server added.');
        _load();
      }
    } finally {
      nameCtrl.dispose();
      cmdCtrl.dispose();
      argsCtrl.dispose();
      urlCtrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tools & MCP'),
        actions: [
          IconButton(
            tooltip: 'Reload MCP',
            icon:  Icon(Icons.cached_rounded,
                color: P.inkSecondary, weight: 1.6),
            onPressed: _reload,
          ),
          IconButton(
            icon:  Icon(Icons.refresh_rounded,
                color: P.inkSecondary, weight: 1.6),
            onPressed: _load,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        backgroundColor: P.accentDeep,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded, weight: 2),
        label:
            const Text('Add', style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: FutureBuilder<
          ({List<McpServerGroup> groups, List<String> pending, String? note})>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return _skeleton();
          }
          if (snap.hasError) {
            return EmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'Couldn\'t load MCP servers',
              body: snap.error.toString(),
              ctaLabel: 'Retry',
              onCta: _load,
            );
          }
          final data = snap.data!;
          final groups =
              data.groups.where((g) => g.servers.isNotEmpty).toList();
          return RefreshIndicator(
            onRefresh: () async => _load(),
            color: P.accent,
            backgroundColor: P.surface,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
              children: [
                if (data.pending.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: PCard(
                      borderColor: P.warn.withValues(alpha: 0.5),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('PENDING APPROVAL',
                              style: PT.overline.copyWith(color: P.warn)),
                          const SizedBox(height: 8),
                          for (final name in data.pending) ...[
                            Row(
                              children: [
                                Expanded(
                                  child: Text(name, style: PT.mono),
                                ),
                                if (_busy.contains(name))
                                  const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2.5, color: P.accent),
                                  )
                                else
                                  PillButton(
                                    label: 'Approve',
                                    filled: false,
                                    color: P.ok,
                                    onTap: () => _approve(name),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                          ],
                          Text(
                            'Approved servers can run; unapproved ones stay inert.',
                            style: PT.meta,
                          ),
                        ],
                      ),
                    ),
                  ),
                if (groups.isEmpty)
                  const EmptyState(
                    icon: Icons.hub_outlined,
                    title: 'No MCP servers',
                    body: 'Add one with the button below.',
                  )
                else
                  for (final g in groups) ...[
                    Overline('${g.source} · ${g.origin}'),
                    for (var i = 0; i < g.servers.length; i++)
                      StaggerItem(index: i, child: _card(g.servers[i])),
                  ],
                if (data.note != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                    child: Text(data.note!,
                        style: PT.meta.copyWith(color: P.inkFaint)),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _card(McpServer s) {
    final busy = _busy.contains(s.name);
    final statusColor = !s.enabled
        ? P.inkFaint
        : (s.readiness == 'ready' ? P.ok : P.warn);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(s.name,
                      style: PT.mono.copyWith(color: P.ink, fontSize: 13)),
                ),
                StatusChip(
                    label: s.enabled
                        ? s.readiness.toUpperCase()
                        : 'DISABLED',
                    color: statusColor),
              ],
            ),
            const SizedBox(height: 6),
            Text(s.describe,
                style: PT.monoSm,
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            if (s.requiresEnv.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: s.requiresEnv
                    .map((e) => PillChip(label: 'env · $e', selected: false))
                    .toList(),
              ),
            ],
            const SizedBox(height: 10),
            if (busy)
               SizedBox(
                height: 36,
                child: Center(
                    child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: P.accent))),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: PillButton(
                      label: s.enabled ? 'Disable' : 'Enable',
                      filled: false,
                      color: s.enabled ? P.warn : P.ok,
                      onTap: () => _toggle(s),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: PillButton(
                      label: 'Test',
                      filled: false,
                      onTap: () => _test(s),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: PillButton(
                      label: 'Delete',
                      filled: false,
                      color: P.err,
                      onTap: () => _delete(s),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _skeleton() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: 4,
      itemBuilder: (_, __) => const Padding(
        padding: EdgeInsets.only(bottom: 10),
        child: Shimmer(width: double.infinity, height: 130, radius: 16),
      ),
    );
  }
}
