import 'package:flutter/material.dart';

import '../models/plugin.dart';
import '../services/pantheon_api.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/chips.dart';
import '../widgets/forms.dart';
import '../widgets/pantheon_card.dart';
import '../widgets/states.dart';

/// Plugins: tool plugins and hook extensions — approve or disable.
class PluginsScreen extends StatefulWidget {
  final PantheonApi api;

  const PluginsScreen({super.key, required this.api});

  @override
  State<PluginsScreen> createState() => _PluginsScreenState();
}

class _PluginsScreenState extends State<PluginsScreen> {
  Future<List<Plugin>>? _future;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() => _future = widget.api.plugins());
  }

  String _key(Plugin p) => '${p.kind}:${p.name}';

  Future<void> _approve(Plugin p) async {
    final ok = await confirmAction(
      context,
      title: 'Approve this ${p.kind}?',
      body: '“${p.name}” will be trusted to run on the runtime.',
      confirmLabel: 'Approve',
    );
    if (!ok || !mounted) return;
    setState(() => _busy.add(_key(p)));
    try {
      await widget.api.approvePlugin(p.kind, p.name);
      if (!mounted) return;
      toast(context, '“${p.name}” approved.');
      _load();
    } catch (e) {
      if (mounted) toastError(context, e);
    } finally {
      if (mounted) setState(() => _busy.remove(_key(p)));
    }
  }

  Future<void> _disable(Plugin p) async {
    final ok = await confirmAction(
      context,
      title: 'Disable this ${p.kind}?',
      body: '“${p.name}” will stop loading on the runtime.',
      confirmLabel: 'Disable',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy.add(_key(p)));
    try {
      await widget.api.disablePlugin(p.kind, p.name);
      if (!mounted) return;
      toast(context, '“${p.name}” disabled.');
      _load();
    } catch (e) {
      if (mounted) toastError(context, e);
    } finally {
      if (mounted) setState(() => _busy.remove(_key(p)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Plugins'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded,
                color: P.inkSecondary, weight: 1.6),
            onPressed: _load,
          ),
        ],
      ),
      body: FutureBuilder<List<Plugin>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return _skeleton();
          }
          if (snap.hasError) {
            return EmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'Couldn\'t load plugins',
              body: snap.error.toString(),
              ctaLabel: 'Retry',
              onCta: _load,
            );
          }
          final plugins = snap.data!;
          if (plugins.isEmpty) {
            return const EmptyState(
              icon: Icons.extension_outlined,
              title: 'No plugins found',
              body: 'Tool plugins and hook extensions will appear here.',
            );
          }
          final tools = plugins.where((p) => p.kind == 'tool').toList();
          final hooks = plugins.where((p) => p.kind != 'tool').toList();
          return RefreshIndicator(
            onRefresh: () async => _load(),
            color: P.accent,
            backgroundColor: P.surface,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                if (tools.isNotEmpty) ...[
                  const Overline('Tool plugins'),
                  for (var i = 0; i < tools.length; i++)
                    StaggerItem(index: i, child: _card(tools[i])),
                ],
                if (hooks.isNotEmpty) ...[
                  const Overline('Hooks'),
                  for (var i = 0; i < hooks.length; i++)
                    StaggerItem(
                        index: i + tools.length, child: _card(hooks[i])),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _card(Plugin p) {
    final busy = _busy.contains(_key(p));
    final statusColor =
        !p.enabled ? P.inkFaint : (!p.approved ? P.warn : P.ok);
    final statusLabel =
        !p.enabled ? 'DISABLED' : (!p.approved ? 'PENDING' : 'ACTIVE');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(p.name,
                      style: PT.mono.copyWith(color: P.ink, fontSize: 13)),
                ),
                if (p.bundled)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: StatusChip(label: 'BUNDLED', color: P.info),
                  ),
                StatusChip(label: statusLabel, color: statusColor),
              ],
            ),
            if (p.description != null && p.description!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(p.description!,
                  style: PT.meta, maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
            if (p.version != null) ...[
              const SizedBox(height: 4),
              Text('v${p.version}', style: PT.faint),
            ],
            const SizedBox(height: 10),
            if (busy)
              const SizedBox(
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
                  if (!p.approved)
                    Expanded(
                      child: PillButton(
                        label: 'Approve',
                        color: P.ok,
                        onTap: () => _approve(p),
                      ),
                    ),
                  if (!p.approved) const SizedBox(width: 8),
                  Expanded(
                    child: PillButton(
                      label: 'Disable',
                      color: P.err,
                      filled: false,
                      onTap: p.enabled ? () => _disable(p) : null,
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
      itemCount: 5,
      itemBuilder: (_, __) => const Padding(
        padding: EdgeInsets.only(bottom: 10),
        child: Shimmer(width: double.infinity, height: 110, radius: 16),
      ),
    );
  }
}
