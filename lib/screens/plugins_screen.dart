import 'package:flutter/material.dart';

import '../models/models.dart';
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

  /// Import sheet: URL + optional ref, then POST /api/plugins/import.
  Future<void> _import() async {
    final urlCtrl = TextEditingController();
    final refCtrl = TextEditingController();
    var busy = false;
    String? urlError;
    try {
      final imported = await showPSheet<Map<String, dynamic>>(
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
                  Text('Import plugin', style: PT.sectionTitle),
                  const SizedBox(height: 16),
                  TextField(
                    controller: urlCtrl,
                    style: PT.mono.copyWith(color: P.ink, fontSize: 13),
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      labelText: 'Plugin URL',
                      hintText: 'https://github.com/…',
                      errorText: urlError,
                    ),
                    onChanged: (_) {
                      if (urlError != null) {
                        setSheet(() => urlError = null);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: refCtrl,
                    style: PT.mono.copyWith(color: P.ink, fontSize: 13),
                    decoration: const InputDecoration(
                      labelText: 'Ref (optional)',
                      hintText: 'branch, tag, or commit',
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
                        child: PillButton(
                          label: busy ? 'Importing…' : 'Import',
                          onTap: busy
                              ? null
                              : () async {
                                  final url = urlCtrl.text.trim();
                                  if (url.isEmpty) {
                                    setSheet(() => urlError =
                                        'Enter a plugin URL first.');
                                    return;
                                  }
                                  setSheet(() => busy = true);
                                  try {
                                    final res = await widget.api.importPlugin(
                                      url: url,
                                      ref: refCtrl.text.trim(),
                                    );
                                    if (ctx.mounted) Navigator.pop(ctx, res);
                                  } catch (e) {
                                    if (ctx.mounted) {
                                      if (e is PantheonStaleBackendException) {
                                        // Endpoint not landed on this gateway
                                        // yet: the app already degrades the
                                        // 404 for it in `_decode`.
                                        toast(ctx,
                                            'Plugin import isn\'t available on this gateway yet.');
                                      } else {
                                        toastError(ctx, e);
                                      }
                                    }
                                  } finally {
                                    if (ctx.mounted) {
                                      setSheet(() => busy = false);
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
      if (imported == null || !mounted) return;
      _load();
      _confirmImported(imported);
    } finally {
      urlCtrl.dispose();
      refCtrl.dispose();
    }
  }

  /// Review sheet after a successful import: scan verdict, detected
  /// capabilities, then approval — imported plugins stay unapproved until
  /// then. `malicious` blocks approval outright; `suspicious` needs an
  /// explicit risk acknowledgement; a missing `scan_report` renders as
  /// "scan unavailable" (amber, non-blocking).
  Future<void> _confirmImported(Map<String, dynamic> res) async {
    final name = res['name'] as String? ?? 'plugin';
    final kind = res['kind'] as String? ?? 'tool';
    final version = res['version'] as String?;
    final caps = (res['detected_capabilities'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
    final scan = res['scan_report'] as Map?;
    final verdict = scan?['verdict'] as String?;
    final findings = (scan?['findings'] as List?)
            ?.whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList() ??
        [];

    final isMalicious = verdict == 'malicious';
    final isSuspicious = verdict == 'suspicious';

    Color scanColor;
    IconData scanIcon;
    String scanLabel;
    if (verdict == 'clean') {
      scanColor = P.ok;
      scanIcon = Icons.verified_outlined;
      scanLabel = 'Scan clean';
    } else if (isSuspicious) {
      scanColor = P.warn;
      scanIcon = Icons.warning_amber_rounded;
      scanLabel =
          'Suspicious — ${findings.length} finding${findings.length == 1 ? '' : 's'}';
    } else if (isMalicious) {
      scanColor = P.err;
      scanIcon = Icons.block_rounded;
      scanLabel = 'Blocked: malicious';
    } else {
      scanColor = P.warn;
      scanIcon = Icons.help_outline_rounded;
      scanLabel = 'Scan unavailable';
    }

    var ack = false;
    // Malicious findings are listed expanded from the start.
    final expanded = <int>{if (isMalicious) for (var i = 0; i < findings.length; i++) i};

    await showPSheet<void>(
      context,
      StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SheetHandle(),
                const SizedBox(height: 8),
                Text('Plugin imported', style: PT.sectionTitle),
                const SizedBox(height: 6),
                Text(
                  'Review before approving — it won’t load until you approve it.',
                  style: PT.meta,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(name,
                          style:
                              PT.mono.copyWith(color: P.ink, fontSize: 14)),
                    ),
                    StatusChip(label: kind.toUpperCase(), color: P.info),
                  ],
                ),
                if (version != null && version.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('v$version', style: PT.faint),
                ],
                const SizedBox(height: 12),
                Text('SCAN RESULT', style: PT.overline),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: scanColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(P.r12),
                    border:
                        Border.all(color: scanColor.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      Icon(scanIcon, size: 18, color: scanColor),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(scanLabel,
                            style: PT.label.copyWith(color: scanColor)),
                      ),
                    ],
                  ),
                ),
                if (isMalicious) ...[
                  const SizedBox(height: 10),
                  Text(
                    'This plugin was blocked by the security scan and cannot be approved.',
                    style: PT.meta.copyWith(color: P.err),
                  ),
                ],
                if (findings.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  for (var i = 0; i < findings.length; i++)
                    _findingTile(
                      findings[i],
                      expanded: expanded.contains(i),
                      onToggle: () => setSheet(() {
                        if (!expanded.remove(i)) expanded.add(i);
                      }),
                    ),
                ],
                const SizedBox(height: 12),
                Text('DETECTED CAPABILITIES', style: PT.overline),
                const SizedBox(height: 8),
                if (caps.isEmpty)
                  Text('None detected.', style: PT.meta)
                else
                  for (final c in caps)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          const Icon(Icons.check_rounded,
                              size: 14, color: P.ok),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(c,
                                style: PT.mono.copyWith(
                                    color: P.inkSecondary, fontSize: 12)),
                          ),
                        ],
                      ),
                    ),
                const SizedBox(height: 20),
                if (isSuspicious)
                  GestureDetector(
                    onTap: () => setSheet(() => ack = !ack),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Row(
                        children: [
                          Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: ack ? P.ok : P.borderStrong,
                                  width: 1.5),
                              color: ack
                                  ? P.ok.withValues(alpha: 0.25)
                                  : Colors.transparent,
                            ),
                            child: ack
                                ? const Icon(Icons.check_rounded,
                                    size: 15, color: P.ok)
                                : null,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text('I understand the risks',
                                style: PT.body.copyWith(fontSize: 13)),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (isMalicious)
                  TonalButton(
                      label: 'Close', onTap: () => Navigator.pop(context))
                else
                  Row(
                    children: [
                      Expanded(
                        child: TonalButton(
                            label: 'Not now',
                            onTap: () => Navigator.pop(context)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Opacity(
                          opacity: (isSuspicious && !ack) ? 0.45 : 1.0,
                          child: PillButton(
                            label: 'Approve',
                            color: P.ok,
                            onTap: (isSuspicious && !ack)
                                ? null
                                : () {
                                    Navigator.pop(context);
                                    if (!mounted) return;
                                    _approve(Plugin(
                                      kind: kind,
                                      name: name,
                                      enabled: true,
                                      bundled: false,
                                      approved: false,
                                    ));
                                  },
                          ),
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
  }

  /// One scan finding: severity + rule header, tap to expand for
  /// description, file, and line.
  Widget _findingTile(Map<String, dynamic> f,
      {required bool expanded, required VoidCallback onToggle}) {
    final severity = f['severity'] as String?;
    final rule = f['rule'] as String? ?? 'finding';
    final desc = f['description'] as String?;
    final file = f['file'] as String?;
    final line = f['line'];
    final sevColor = switch (severity) {
      'critical' || 'high' => P.err,
      'medium' => P.warn,
      _ => P.info,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: onToggle,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: P.tonal,
            borderRadius: BorderRadius.circular(P.r12),
            border: Border.all(color: P.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (severity != null && severity.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: StatusChip(
                          label: severity.toUpperCase(), color: sevColor),
                    ),
                  Expanded(
                    child: Text(rule,
                        style: PT.mono
                            .copyWith(color: P.ink, fontSize: 12)),
                  ),
                  Icon(
                      expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 18,
                      color: P.inkSecondary),
                ],
              ),
              if (expanded) ...[
                const SizedBox(height: 8),
                if (desc != null && desc.isNotEmpty)
                  Text(desc, style: PT.meta),
                if (file != null && file.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(line != null ? '$file:$line' : file, style: PT.faint),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Plugins'),
        actions: [
          IconButton(
            icon: Icon(Icons.download_rounded,
                color: P.inkSecondary, weight: 1.6),
            tooltip: 'Import plugin',
            onPressed: _import,
          ),
          IconButton(
            icon:  Icon(Icons.refresh_rounded,
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
