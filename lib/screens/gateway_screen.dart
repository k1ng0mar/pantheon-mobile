import 'package:flutter/material.dart';

import '../widgets/chips.dart';

import '../models/models.dart';
import '../services/pantheon_api.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/forms.dart';
import '../widgets/pantheon_card.dart';
import '../widgets/states.dart';

/// Gateway: status of the always-on service (chat surfaces + scheduled
/// tasks) with a restart action.
class GatewayScreen extends StatefulWidget {
  final PantheonApi api;

  const GatewayScreen({super.key, required this.api});

  @override
  State<GatewayScreen> createState() => _GatewayScreenState();
}

class _GatewayScreenState extends State<GatewayScreen> {
  Future<GatewayStatus>? _future;
  bool _restarting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() => _future = widget.api.gatewayStatus());
  }

  Future<void> _restart() async {
    final ok = await confirmAction(
      context,
      title: 'Restart the gateway?',
      body: 'The always-on service (chat surfaces, scheduled tasks) '
          'will restart. In-flight deliveries may be interrupted.',
      confirmLabel: 'Restart',
    );
    if (!ok || !mounted) return;
    setState(() => _restarting = true);
    try {
      await widget.api.restartGateway();
      if (!mounted) return;
      toast(context, 'Gateway restart requested.');
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) _load();
    } catch (e) {
      if (mounted) toastError(context, e);
    } finally {
      if (mounted) setState(() => _restarting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gateway'),
        actions: [
          IconButton(
            icon:  Icon(Icons.refresh_rounded,
                color: P.inkSecondary, weight: 1.6),
            onPressed: _load,
          ),
        ],
      ),
      body: FutureBuilder<GatewayStatus>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return  Center(
                child: CircularProgressIndicator(color: P.accent));
          }
          if (snap.hasError) {
            return EmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'Couldn\'t load gateway status',
              body: snap.error.toString(),
              ctaLabel: 'Retry',
              onCta: _load,
            );
          }
          final g = snap.data!;
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
                              color: g.running
                                  ? P.ok.withValues(alpha: 0.12)
                                  : P.inkFaint.withValues(alpha: 0.12),
                              borderRadius:
                                  BorderRadius.circular(P.r14),
                            ),
                            child: Icon(
                              Icons.hub_rounded,
                              color: g.running ? P.ok : P.inkFaint,
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
                                    g.running
                                        ? 'Running'
                                        : 'Not running',
                                    style: PT.sectionTitle),
                                const SizedBox(height: 2),
                                Text(
                                  'detected · ${g.detected}',
                                  style: PT.meta,
                                ),
                              ],
                            ),
                          ),
                          if (g.running)
                            const LiveDot(size: 12)
                          else
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: P.inkFaint, width: 2),
                              ),
                            ),
                        ],
                      ),
                      if (g.installed != null) ...[
                        const SizedBox(height: 12),
                        KvRow('installed', g.installed!, mono: true),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        'The gateway is the always-on service: chat surfaces '
                        '(Telegram, Discord) and scheduled tasks. The mobile '
                        'app talks to the dashboard directly, so it works '
                        'whether or not the gateway is up.',
                        style: PT.meta.copyWith(color: P.inkFaint),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: GradientButton(
                    label: _restarting ? 'Restarting…' : 'Restart gateway',
                    icon: Icons.refresh_rounded,
                    onTap: _restarting ? null : _restart,
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
