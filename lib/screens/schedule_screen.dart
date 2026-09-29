import 'package:flutter/material.dart';

import '../models/scheduled_job.dart';
import '../models/schedule_template.dart';
import '../services/pantheon_api.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/chips.dart';
import '../widgets/forms.dart';
import '../widgets/pantheon_card.dart';
import '../widgets/states.dart';

/// Tasks: scheduled jobs (CRUD + trigger) and templates, wired to
/// `/api/schedule/*`.
class ScheduleScreen extends StatefulWidget {
  final PantheonApi api;

  const ScheduleScreen({super.key, required this.api});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  Future<List<ScheduledJob>>? _jobsFuture;
  Future<List<ScheduleTemplate>>? _templatesFuture;
  int _tab = 0; // 0 = jobs, 1 = templates
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _loadJobs();
    _loadTemplates();
  }

  void _loadJobs() {
    setState(() => _jobsFuture = widget.api.scheduleJobs());
  }

  void _loadTemplates() {
    setState(() => _templatesFuture = widget.api.scheduleTemplates());
  }

  Future<void> _togglePaused(ScheduledJob j) async {
    setState(() => _busy.add(j.id));
    try {
      await widget.api.updateJob(j.id, {'paused': !j.paused});
      if (mounted) {
        toast(context, j.paused ? 'Job resumed.' : 'Job paused.');
        _loadJobs();
      }
    } catch (e) {
      if (mounted) toastError(context, e);
    } finally {
      if (mounted) setState(() => _busy.remove(j.id));
    }
  }

  Future<void> _trigger(ScheduledJob j) async {
    final ok = await confirmAction(
      context,
      title: 'Run this job now?',
      body: '“${_short(j.task)}” will fire immediately.',
      confirmLabel: 'Run now',
    );
    if (!ok || !mounted) return;
    try {
      await widget.api.triggerJob(j.id);
      if (mounted) toast(context, 'Job triggered.');
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  Future<void> _deleteJob(ScheduledJob j) async {
    final ok = await confirmAction(
      context,
      title: 'Delete this job?',
      body: '“${_short(j.task)}” will be removed permanently.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await widget.api.deleteJob(j.id);
      if (mounted) {
        toast(context, 'Job deleted.');
        _loadJobs();
      }
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  Future<void> _deleteTemplate(ScheduleTemplate t) async {
    final ok = await confirmAction(
      context,
      title: 'Delete template?',
      body: '“${t.name}” will be removed permanently.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await widget.api.deleteTemplate(t.name);
      if (mounted) {
        toast(context, 'Template deleted.');
        _loadTemplates();
      }
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  static String _short(String s) =>
      s.length > 60 ? '${s.substring(0, 60)}…' : s;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tasks'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded,
                color: P.inkSecondary, weight: 1.6),
            onPressed: () {
              _loadJobs();
              _loadTemplates();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            _tab == 0 ? _createJobSheet() : _createTemplateSheet(),
        backgroundColor: P.accentDeep,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded, weight: 2),
        label: Text(_tab == 0 ? 'New job' : 'New template',
            style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Row(
              children: [
                _segTab(0, 'Jobs'),
                const SizedBox(width: 8),
                _segTab(1, 'Templates'),
              ],
            ),
          ),
          Expanded(
            child: _tab == 0 ? _jobsList() : _templatesList(),
          ),
        ],
      ),
    );
  }

  Widget _segTab(int i, String label) {
    final selected = _tab == i;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tab = i),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: selected ? P.accentSoft : Colors.transparent,
            border: Border.all(
                color: selected ? P.accent : P.borderStrong, width: 1),
          ),
          alignment: Alignment.center,
          child: Text(label,
              style: PT.label.copyWith(
                  fontSize: 13,
                  color: selected ? P.ink : P.inkSecondary)),
        ),
      ),
    );
  }

  // ------------------------------------------------------------- jobs ---

  Widget _jobsList() {
    return FutureBuilder<List<ScheduledJob>>(
      future: _jobsFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return _skeleton(96);
        }
        if (snap.hasError) {
          return EmptyState(
            icon: Icons.cloud_off_outlined,
            title: 'Couldn\'t load jobs',
            body: snap.error.toString(),
            ctaLabel: 'Retry',
            onCta: _loadJobs,
          );
        }
        final jobs = snap.data!;
        if (jobs.isEmpty) {
          return const EmptyState(
            icon: Icons.schedule_outlined,
            title: 'No scheduled jobs',
            body: 'Create one with the button below.',
          );
        }
        return RefreshIndicator(
          onRefresh: () async => _loadJobs(),
          color: P.accent,
          backgroundColor: P.surface,
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            itemCount: jobs.length,
            itemBuilder: (context, i) =>
                StaggerItem(index: i, child: _jobCard(jobs[i])),
          ),
        );
      },
    );
  }

  Widget _jobCard(ScheduledJob j) {
    final busy = _busy.contains(j.id);
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
            const SizedBox(height: 12),
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
                  Expanded(
                    child: PillButton(
                      label: 'Run now',
                      filled: false,
                      onTap: () => _trigger(j),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: PillButton(
                      label: j.paused ? 'Resume' : 'Pause',
                      filled: false,
                      color: P.warn,
                      onTap: () => _togglePaused(j),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: PillButton(
                      label: 'Delete',
                      filled: false,
                      color: P.err,
                      onTap: () => _deleteJob(j),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _createJobSheet() async {
    final taskCtrl = TextEditingController();
    final everyCtrl = TextEditingController(text: '1h');
    final cronCtrl = TextEditingController();
    final agentCtrl = TextEditingController();
    final modelCtrl = TextEditingController();
    String kind = 'every';
    DateTime? onceAt;    try {
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
                  const Text('New scheduled job', style: PT.sectionTitle),
                  const SizedBox(height: 16),
                  TextField(
                    controller: taskCtrl,
                    minLines: 2,
                    maxLines: 4,
                    style: PT.body,
                    decoration: const InputDecoration(
                      labelText: 'Task',
                      hintText: 'What should the agent do?',
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('SCHEDULE', style: PT.overline),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _kindChip(setSheet, 'every', 'Every', kind,
                          (v) => kind = v),
                      const SizedBox(width: 8),
                      _kindChip(
                          setSheet, 'cron', 'Cron', kind, (v) => kind = v),
                      const SizedBox(width: 8),
                      _kindChip(
                          setSheet, 'once', 'Once', kind, (v) => kind = v),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (kind == 'every')
                    TextField(
                      controller: everyCtrl,
                      style: PT.body,
                      decoration: const InputDecoration(
                        labelText: 'Interval',
                        hintText: 'e.g. 30m, 2h, 1d',
                      ),
                    ),
                  if (kind == 'cron')
                    TextField(
                      controller: cronCtrl,
                      style: PT.mono.copyWith(color: P.ink),
                      decoration: const InputDecoration(
                        labelText: 'Cron expression',
                        hintText: 'e.g. 0 9 * * *',
                      ),
                    ),
                  if (kind == 'once')
                    TonalButton(
                      label: onceAt == null
                          ? 'Pick date & time'
                          : '${onceAt!.year}-${onceAt!.month.toString().padLeft(2, '0')}-${onceAt!.day.toString().padLeft(2, '0')} '
                              '${onceAt!.hour.toString().padLeft(2, '0')}:${onceAt!.minute.toString().padLeft(2, '0')}',
                      onTap: () async {
                        final d = await showDatePicker(
                          context: ctx,
                          initialDate:
                              DateTime.now().add(const Duration(hours: 1)),
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now()
                              .add(const Duration(days: 365)),
                        );
                        if (d == null || !ctx.mounted) return;
                        final t = await showTimePicker(
                          context: ctx,
                          initialTime: TimeOfDay.now(),
                        );
                        if (t == null) return;
                        setSheet(() => onceAt = DateTime(
                            d.year, d.month, d.day, t.hour, t.minute));
                      },
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: agentCtrl,
                          style: PT.body,
                          decoration: const InputDecoration(
                              labelText: 'Agent (optional)'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: modelCtrl,
                          style: PT.body,
                          decoration: const InputDecoration(
                              labelText: 'Model (optional)'),
                        ),
                      ),
                    ],
                  ),
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
                          label: 'Create',
                          onTap: () async {
                            final body = <String, dynamic>{
                              'task': taskCtrl.text.trim(),
                            };
                            if (kind == 'every') {
                              body['every'] = everyCtrl.text.trim();
                            } else if (kind == 'cron') {
                              body['cron'] = cronCtrl.text.trim();
                            } else {
                              if (onceAt == null) {
                                toast(ctx, 'Pick a date & time first.');
                                return;
                              }
                              body['at_ms'] =
                                  onceAt!.millisecondsSinceEpoch;
                            }
                            if (agentCtrl.text.trim().isNotEmpty) {
                              body['agent'] = agentCtrl.text.trim();
                            }
                            if (modelCtrl.text.trim().isNotEmpty) {
                              body['model'] = modelCtrl.text.trim();
                            }
                            try {
                              await widget.api.createJob(body);
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
        toast(context, 'Job created.');
        _loadJobs();
      }
    } finally {
      taskCtrl.dispose();
      everyCtrl.dispose();
      cronCtrl.dispose();
      agentCtrl.dispose();
      modelCtrl.dispose();
    }
  }

  Widget _kindChip(StateSetter setSheet, String value, String label,
      String current, ValueChanged<String> onSelect) {
    final selected = value == current;
    return Expanded(
      child: GestureDetector(
        onTap: () => setSheet(() => onSelect(value)),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: selected ? P.accentSoft : Colors.transparent,
            border: Border.all(
                color: selected ? P.accent : P.borderStrong, width: 1),
          ),
          alignment: Alignment.center,
          child: Text(label,
              style: PT.label.copyWith(
                  fontSize: 13,
                  color: selected ? P.ink : P.inkSecondary)),
        ),
      ),
    );
  }

  // -------------------------------------------------------- templates ---

  Widget _templatesList() {
    return FutureBuilder<List<ScheduleTemplate>>(
      future: _templatesFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return _skeleton(80);
        }
        if (snap.hasError) {
          return EmptyState(
            icon: Icons.cloud_off_outlined,
            title: 'Couldn\'t load templates',
            body: snap.error.toString(),
            ctaLabel: 'Retry',
            onCta: _loadTemplates,
          );
        }
        final templates = snap.data!;
        if (templates.isEmpty) {
          return const EmptyState(
            icon: Icons.description_outlined,
            title: 'No templates',
            body: 'Templates turn prompts into reusable scheduled jobs.',
          );
        }
        return RefreshIndicator(
          onRefresh: () async => _loadTemplates(),
          color: P.accent,
          backgroundColor: P.surface,
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            itemCount: templates.length,
            itemBuilder: (context, i) =>
                StaggerItem(index: i, child: _templateCard(templates[i])),
          ),
        );
      },
    );
  }

  Widget _templateCard(ScheduleTemplate t) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(t.name,
                      style: PT.mono.copyWith(color: P.ink, fontSize: 13)),
                ),
                PillChip(
                    label: '${t.scheduleType} · ${t.scheduleDetail}',
                    selected: false),
              ],
            ),
            if (t.description != null && t.description!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(t.description!, style: PT.meta),
            ],
            if (t.vars.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: t.vars
                    .map((v) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: P.tonal,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: P.border),
                          ),
                          child: Text(
                            v.defaultValue != null
                                ? '${v.name} = ${v.defaultValue}'
                                : v.name,
                            style: PT.monoSm,
                          ),
                        ))
                    .toList(),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: PillButton(
                    label: 'Delete',
                    filled: false,
                    color: P.err,
                    onTap: () => _deleteTemplate(t),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createTemplateSheet() async {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final schedCtrl = TextEditingController(text: '1h');
    String schedKind = 'every'; // every | cron
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
                  const Text('New template', style: PT.sectionTitle),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameCtrl,
                    style: PT.mono.copyWith(color: P.ink),
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      hintText: 'e.g. morning-brief',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtrl,
                    minLines: 2,
                    maxLines: 3,
                    style: PT.body,
                    decoration: const InputDecoration(
                      labelText: 'Description (optional)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: PillChip(
                          label: 'every',
                          selected: schedKind == 'every',
                          onTap: () => setSheet(() => schedKind = 'every'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: PillChip(
                          label: 'cron',
                          selected: schedKind == 'cron',
                          onTap: () => setSheet(() => schedKind = 'cron'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: schedCtrl,
                    style: PT.body,
                    decoration: InputDecoration(
                      labelText:
                          schedKind == 'every' ? 'Interval' : 'Cron expression',
                      hintText: schedKind == 'every'
                          ? 'e.g. 30m, 2h, 1d'
                          : 'e.g. 0 9 * * *',
                    ),
                  ),
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
                          label: 'Create',
                          onTap: () async {
                            final name = nameCtrl.text.trim();
                            if (name.isEmpty) return;
                            final body = {
                              'name': name,
                              'description': descCtrl.text.trim(),
                              'schedule': {
                                if (schedKind == 'every')
                                  'every': schedCtrl.text.trim()
                                else
                                  'cron': schedCtrl.text.trim(),
                              },
                            };
                            try {
                              await widget.api.createTemplate(body);
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
        toast(context, 'Template created.');
        _loadTemplates();
      }
    } finally {
      nameCtrl.dispose();
      descCtrl.dispose();
      schedCtrl.dispose();
    }
  }

  Widget _skeleton(double h) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: 4,
      itemBuilder: (_, __) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Shimmer(width: double.infinity, height: h, radius: 16),
      ),
    );
  }
}
