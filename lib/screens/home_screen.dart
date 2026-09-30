import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/pantheon_api.dart';
import '../theme.dart';
import '../widgets/chips.dart';
import '../widgets/pantheon_card.dart';
import '../widgets/states.dart';

class HomeScreen extends StatefulWidget {
  final PantheonApi api;
  final ValueNotifier<int> pendingApprovals;

  const HomeScreen(
      {super.key, required this.api, required this.pendingApprovals});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Future<(Overview, GatewayStatus)>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _future = Future.wait([
        widget.api.overview(),
        widget.api.gatewayStatus(),
      ]).then((v) {
        widget.pendingApprovals.value = (v[0] as Overview).approvalsPending;
        return (v[0] as Overview, v[1] as GatewayStatus);
      });
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Overview'),
        actions: [
          IconButton(
            icon:  Icon(Icons.refresh_rounded,
                color: P.inkSecondary, weight: 1.6),
            onPressed: _load,
          ),
        ],
      ),
      body: FutureBuilder<(Overview, GatewayStatus)>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return _skeleton();
          }
          if (snap.hasError) {
            return _error(snap.error.toString());
          }
          final ov = snap.data!.$1;
          final gw = snap.data!.$2;
          return RefreshIndicator(
            onRefresh: () async => _load(),
            color: P.accent,
            backgroundColor: P.surface,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                const Overline('Gateway'),
                StaggerItem(index: 0, child: _gatewayCard(gw)),
                const Overline('Today'),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.35,
                  children: [
                    StaggerItem(
                        index: 1,
                        child: _kpi(
                            'Total runs',
                            Text('${ov.totalRuns}',
                                style: PT.screenTitle
                                    .copyWith(fontSize: 24)),
                            Icons.bolt_outlined,
                            P.info)),
                    StaggerItem(
                        index: 2,
                        child: _kpi(
                            'Awaiting approval',
                            Text('${ov.approvalsPending}',
                                style: PT.screenTitle
                                    .copyWith(fontSize: 24)),
                            Icons.rule_outlined,
                            P.warn)),
                    StaggerItem(
                        index: 3,
                        child: _kpi(
                            'Cost · 24h',
                            CountUp(
                                value: ov.cost24h,
                                format: (v) => money(v),
                                style: PT.screenTitle
                                    .copyWith(fontSize: 24)),
                            Icons.payments_outlined,
                            P.ok)),
                    StaggerItem(
                        index: 4,
                        child: _kpi(
                            'Tokens · 24h',
                            CountUp(
                                value: ov.tokens24h,
                                format: (v) => compactNum(v),
                                style: PT.screenTitle
                                    .copyWith(fontSize: 24)),
                            Icons.token_outlined,
                            P.accent)),
                  ],
                ),
                const Overline('Runs by status'),
                StaggerItem(index: 5, child: _statusCard(ov)),
                const Overline('Scheduler'),
                StaggerItem(
                  index: 6,
                  child: PCard(
                    padding: EdgeInsets.zero,
                    child: PRow(
                      title: '${ov.jobsActive} active · ${ov.jobsTotal} total',
                      subtitle: 'recurring jobs',
                      dotColor: ov.jobsActive > 0 ? P.ok : P.inkFaint,
                      dotHollow: ov.jobsActive == 0,
                      supporting: '${ov.jobsTotal}',
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _gatewayCard(GatewayStatus gw) {
    final running = gw.running;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: P.tonal,
        borderRadius: BorderRadius.circular(P.r16),
      ),
      child: Row(
        children: [
          if (running)
            const LiveDot()
          else
             StatusDot(color: P.inkFaint, hollow: true),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Gateway ${running ? 'running' : 'not running'}',
                    style: PT.rowTitle),
                const SizedBox(height: 2),
                Text(
                  '${gw.detected}${gw.installed != null ? ' · ${gw.installed}' : ''}',
                  style: PT.monoSm.copyWith(color: P.inkMuted),
                ),
              ],
            ),
          ),
          StatusChip(
              label: running ? 'LIVE' : 'IDLE',
              color: running ? P.ok : P.inkFaint),
        ],
      ),
    );
  }

  Widget _kpi(String label, Widget value, IconData icon, Color accent) {
    return PCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, size: 20, color: accent, weight: 1.6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              value,
              const SizedBox(height: 2),
              Text(label, style: PT.faint),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusCard(Overview ov) {
    if (ov.byStatus.isEmpty) {
      return  PCard(child: Text('No runs yet.', style: PT.small));
    }
    final entries = ov.byStatus.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return PRowCard(
      rows: [
        for (final e in entries)
          PRow(
            title: _prettyStatus(e.key),
            dotColor: _statusColor(e.key),
            supporting: '${e.value}',
          ),
      ],
    );
  }

  String _prettyStatus(String s) => s
      .replaceAll('_', ' ')
      .split(' ')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');

  Widget _skeleton() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      children: const [
        Shimmer(width: double.infinity, height: 84, radius: 16),
        SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: Shimmer(width: 0, height: 120, radius: 16)),
            SizedBox(width: 12),
            Expanded(child: Shimmer(width: 0, height: 120, radius: 16)),
          ],
        ),
        SizedBox(height: 12),
        Shimmer(width: double.infinity, height: 140, radius: 16),
      ],
    );
  }

  Widget _error(String msg) {
    return EmptyState(
      icon: Icons.cloud_off_outlined,
      title: 'Couldn\'t reach the dashboard',
      body: msg,
      ctaLabel: 'Retry',
      onCta: _load,
    );
  }
}
