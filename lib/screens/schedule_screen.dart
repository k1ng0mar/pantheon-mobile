import 'package:flutter/material.dart';

import '../models/scheduled_job.dart';
import '../services/pantheon_api.dart';
import '../theme.dart';
import '../widgets/chips.dart';
import '../widgets/pantheon_card.dart';
import '../widgets/states.dart';

class ScheduleScreen extends StatefulWidget {
  final PantheonApi api;

  const ScheduleScreen({super.key, required this.api});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  Future<List<ScheduledJob>>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() => _future = widget.api.scheduleJobs());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Schedule'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded,
                color: P.inkSecondary, weight: 1.6),
            onPressed: _load,
          ),
        ],
      ),
      body: FutureBuilder<List<ScheduledJob>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return _skeleton();
          }
          if (snap.hasError) {
            return EmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'Couldn\'t load jobs',
              body: snap.error.toString(),
              ctaLabel: 'Retry',
              onCta: _load,
            );
          }
          final jobs = snap.data!;
          if (jobs.isEmpty) {
            return const EmptyState(
              icon: Icons.schedule_outlined,
              title: 'No scheduled jobs',
              body: 'Jobs you schedule on the runtime will appear here.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => _load(),
            color: P.accent,
            backgroundColor: P.surface,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              itemCount: jobs.length,
              itemBuilder: (context, i) =>
                  StaggerItem(index: i, child: _jobCard(jobs[i])),
            ),
          );
        },
      ),
    );
  }

  Widget _jobCard(ScheduledJob j) {
    final parts = [
      if (j.agent != null) 'agent · ${j.agent}',
      if (j.model != null) '${j.model}',
      if (j.lastRunMs != null) 'last run ${timeAgo(j.lastRunMs!)}',
      if (j.nextFireMs != null && !j.paused)
        'next ${timeAgo(j.nextFireMs!, future: true)}',
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StatusDot(
                    color: j.paused ? P.inkFaint : P.ok, hollow: j.paused),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(j.task,
                      style: PT.rowTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                StatusChip(
                    label: j.paused ? 'PAUSED' : 'ACTIVE',
                    color: j.paused ? P.inkFaint : P.ok),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                PillChip(label: j.kind.display, selected: false),
                ...parts.map((p) => Text(p, style: PT.meta)),
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
        child: Shimmer(width: double.infinity, height: 96, radius: 16),
      ),
    );
  }
}
