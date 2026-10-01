import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/pantheon_api.dart';
import '../theme.dart';
import '../widgets/forms.dart';
import '../widgets/pantheon_card.dart';
import '../widgets/states.dart';

/// Nightly repair loop: enable state, why it's on/off, next and last run.
class NightlyScreen extends StatefulWidget {
  final PantheonApi api;

  const NightlyScreen({super.key, required this.api});

  @override
  State<NightlyScreen> createState() => _NightlyScreenState();
}

class _NightlyScreenState extends State<NightlyScreen> {
  Future<NightlyStatus>? _future;
  bool _toggling = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() => _future = widget.api.nightlyStatus());
  }

  Future<void> _toggle(bool enable) async {
    final ok = await confirmAction(
      context,
      title: enable ? 'Enable nightly repair?' : 'Disable nightly repair?',
      body: enable
          ? 'Pantheon will run its nightly pass — repairing broken evals, '
              'MCP servers, scheduled tasks, and tools (bounded repair, '
              'then disable-with-escalation).'
          : 'The nightly pass stops running. Nothing else changes.',
      confirmLabel: enable ? 'Enable' : 'Disable',
    );
    if (!ok || !mounted) return;
    setState(() => _toggling = true);
    try {
      final status = await widget.api.setNightlyEnabled(enable);
      if (!mounted) return;
      toast(context,
          status.enabled ? 'Nightly repair enabled.' : 'Nightly repair disabled.');
      _load();
    } catch (e) {
      if (mounted) toastError(context, e);
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nightly repair'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded,
                color: P.inkSecondary, weight: 1.6),
            onPressed: _load,
          ),
        ],
      ),
      body: FutureBuilder<NightlyStatus>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(
                child: CircularProgressIndicator(color: P.accent));
          }
          if (snap.hasError) {
            return EmptyState(
              icon: Icons.nights_stay_outlined,
              title: 'Couldn\'t load nightly status',
              body: snap.error.toString(),
              ctaLabel: 'Retry',
              onCta: _load,
            );
          }
          final s = snap.data!;
          return RefreshIndicator(
            onRefresh: () async => _load(),
            color: P.accent,
            backgroundColor: P.surface,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                PCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: s.enabled
                                  ? P.ok.withValues(alpha: 0.12)
                                  : P.inkFaint.withValues(alpha: 0.12),
                              borderRadius:
                                  BorderRadius.circular(P.r14),
                            ),
                            child: Icon(
                              Icons.nights_stay_rounded,
                              color: s.enabled ? P.ok : P.inkFaint,
                              size: 24,
                              weight: 1.6,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                    s.enabled
                                        ? 'Enabled'
                                        : 'Disabled',
                                    style: PT.sectionTitle),
                                const SizedBox(height: 2),
                                Text(s.reason, style: PT.meta),
                              ],
                            ),
                          ),
                          Switch(
                            value: s.enabled,
                            activeTrackColor: P.accent,
                            onChanged:
                                _toggling ? null : (v) => _toggle(v),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (s.nextRunMs != null)
                        KvRow('next run',
                            timeAgo(s.nextRunMs!, future: true),
                            mono: true)
                      else
                        const KvRow('next run', 'not scheduled'),
                      if (s.lastRunMs > 0) ...[
                        const SizedBox(height: 6),
                        KvRow('last run', timeAgo(s.lastRunMs),
                            mono: true),
                      ],
                      if (s.modelPin) ...[
                        const SizedBox(height: 6),
                        const KvRow('repair model', 'pinned',
                            mono: true),
                      ],
                      if (s.lastSummary.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(s.lastSummary,
                            style: PT.meta
                                .copyWith(color: P.inkSecondary)),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        'The nightly pass detects and repairs broken evals, '
                        'MCP servers, scheduled tasks, and tools. Repairs are '
                        'bounded — anything it can\'t fix is disabled and '
                        'escalated, never silently dropped.',
                        style: PT.meta.copyWith(color: P.inkFaint),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
