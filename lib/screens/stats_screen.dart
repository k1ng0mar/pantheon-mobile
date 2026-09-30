import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/pantheon_api.dart';
import '../theme.dart';
import '../widgets/chips.dart';
import '../widgets/pantheon_card.dart';
import '../widgets/states.dart';

class StatsScreen extends StatefulWidget {
  final PantheonApi api;

  const StatsScreen({super.key, required this.api});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  int _days = 30;
  Future<UsageStats>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() => _future = widget.api.stats(days: _days));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Usage'),
        actions: [
          IconButton(
            icon:  Icon(Icons.refresh_rounded,
                color: P.inkSecondary, weight: 1.6),
            onPressed: _load,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Row(
              children: [
                for (final d in [7, 30, 90])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: PillChip(
                      label: '${d}d',
                      selected: _days == d,
                      onTap: () {
                        setState(() => _days = d);
                        _load();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<UsageStats>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return _skeleton();
                }
                if (snap.hasError) {
                  return EmptyState(
                    icon: Icons.cloud_off_outlined,
                    title: 'Couldn\'t load usage',
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
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      const Overline('Totals'),
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 1.35,
                        children: [
                          StaggerItem(
                              index: 0,
                              child: _kpi('Cost', s.totals.costUsd,
                                  (v) => money(v), P.ok)),
                          StaggerItem(
                              index: 1,
                              child: _kpi('Tokens', s.totals.totalTokens,
                                  (v) => compactNum(v), P.accent)),
                          StaggerItem(
                              index: 2,
                              child: _kpi('Input', s.totals.inputTokens,
                                  (v) => compactNum(v), P.info)),
                          StaggerItem(
                              index: 3,
                              child: _kpi('Output', s.totals.outputTokens,
                                  (v) => compactNum(v), P.warn)),
                        ],
                      ),
                      const Overline('Per day'),
                      StaggerItem(index: 4, child: _dayBars(s)),
                      const Overline('By model'),
                      StaggerItem(index: 5, child: _modelCard(s)),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpi(String label, num value, String Function(num) fmt, Color accent) {
    return PCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: accent),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CountUp(
                  value: value,
                  format: fmt,
                  style: PT.screenTitle.copyWith(fontSize: 24)),
              const SizedBox(height: 2),
              Text(label, style: PT.faint),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dayBars(UsageStats s) {
    final days = s.byDay.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    if (days.isEmpty) {
      return  PCard(child: Text('No daily data.', style: PT.small));
    }
    final maxCost = days
        .map((e) => e.value.costUsd)
        .fold<double>(0, (a, b) => a > b ? a : b);
    return PCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 140,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final e in days)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: _Bar(
                        frac: maxCost == 0 ? 0 : e.value.costUsd / maxCost,
                        label: e.key.length > 5 ? e.key.substring(5) : e.key,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text('cost per day · ${money(s.totals.costUsd)} total',
              style: PT.faint),
        ],
      ),
    );
  }

  Widget _modelCard(UsageStats s) {
    final models = s.byModel.entries.toList()
      ..sort((a, b) => b.value.costUsd.compareTo(a.value.costUsd));
    if (models.isEmpty) {
      return  PCard(child: Text('No model data.', style: PT.small));
    }
    final maxCost = models.first.value.costUsd;
    return PCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < models.length; i++) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(models[i].key,
                            style: PT.rowTitle.copyWith(fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                      Text(money(models[i].value.costUsd), style: PT.monoSm),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(
                          begin: 0,
                          end: maxCost == 0
                              ? 0
                              : models[i].value.costUsd / maxCost),
                      duration: Duration(milliseconds: 700 + i * 80),
                      curve: Curves.easeOutCubic,
                      builder: (_, v, __) => LinearProgressIndicator(
                        value: v,
                        minHeight: 6,
                        backgroundColor: P.tonal,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(P.accent),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                      '${compactNum(models[i].value.totalTokens)} tok · ${models[i].value.calls} calls',
                      style: PT.faint),
                ],
              ),
            ),
            if (i < models.length - 1)
              const Divider(height: 1, thickness: 1, indent: 14, endIndent: 14),
          ],
        ],
      ),
    );
  }

  Widget _skeleton() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      children: const [
        Row(
          children: [
            Expanded(child: Shimmer(width: 0, height: 120, radius: 16)),
            SizedBox(width: 12),
            Expanded(child: Shimmer(width: 0, height: 120, radius: 16)),
          ],
        ),
        SizedBox(height: 12),
        Shimmer(width: double.infinity, height: 180, radius: 16),
      ],
    );
  }
}

/// Animated bar for the per-day chart.
class _Bar extends StatefulWidget {
  final double frac;
  final String label;

  const _Bar({required this.frac, required this.label});

  @override
  State<_Bar> createState() => _BarState();
}

class _BarState extends State<_Bar> {
  bool _in = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => mounted ? setState(() => _in = true) : null);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              heightFactor: _in ? widget.frac.clamp(0.02, 1.0) : 0.02,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [P.accent, P.accentDeep],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(widget.label,
            style: PT.faint.copyWith(fontSize: 9),
            maxLines: 1,
            overflow: TextOverflow.clip),
      ],
    );
  }
}
