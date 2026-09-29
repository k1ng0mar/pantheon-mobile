import 'package:flutter/material.dart';

import '../models/skill.dart';
import '../services/pantheon_api.dart';
import '../theme.dart';
import '../widgets/chips.dart';
import '../widgets/forms.dart';
import '../widgets/pantheon_card.dart';
import '../widgets/states.dart';

/// Skills: list, toggle, import from URL, delete (pantheon-scope).
class SkillsScreen extends StatefulWidget {
  final PantheonApi api;

  const SkillsScreen({super.key, required this.api});

  @override
  State<SkillsScreen> createState() => _SkillsScreenState();
}

class _SkillsScreenState extends State<SkillsScreen> {
  Future<List<Skill>>? _future;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() => _future = widget.api.skills());
  }

  Future<void> _toggle(Skill s) async {
    setState(() => _busy.add(s.name));
    try {
      final enabled = await widget.api.toggleSkill(s.name);
      if (!mounted) return;
      toast(context, enabled ? '“${s.name}” enabled.' : '“${s.name}” disabled.');
      _load();
    } catch (e) {
      if (mounted) toastError(context, e);
    } finally {
      if (mounted) setState(() => _busy.remove(s.name));
    }
  }

  Future<void> _import() async {
    final url = await promptText(
      context,
      title: 'Import skill',
      label: 'Git URL',
      hint: 'https://…',
      keyboardType: TextInputType.url,
      confirmLabel: 'Import',
    );
    if (url == null || !mounted) return;
    final ok = await confirmAction(
      context,
      title: 'Import this skill?',
      body: 'Pantheon will clone $url and install any SKILL.md it finds.',
      confirmLabel: 'Import',
    );
    if (!ok || !mounted) return;
    try {
      await widget.api.importSkill(url);
      if (!mounted) return;
      toast(context, 'Skill imported.');
      _load();
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  Future<void> _delete(Skill s) async {
    final ok = await confirmAction(
      context,
      title: 'Delete skill?',
      body: '“${s.name}” will be removed from the pantheon scope permanently.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await widget.api.deleteSkill(s.name);
      if (!mounted) return;
      toast(context, 'Skill deleted.');
      _load();
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Skills'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded,
                color: P.inkSecondary, weight: 1.6),
            onPressed: _load,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _import,
        backgroundColor: P.accentDeep,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.download_rounded, weight: 2),
        label: const Text('Import',
            style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: FutureBuilder<List<Skill>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return _skeleton();
          }
          if (snap.hasError) {
            return EmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'Couldn\'t load skills',
              body: snap.error.toString(),
              ctaLabel: 'Retry',
              onCta: _load,
            );
          }
          final skills = snap.data!;
          if (skills.isEmpty) {
            return const EmptyState(
              icon: Icons.extension_outlined,
              title: 'No skills installed',
              body: 'Import one with the button below.',
            );
          }
          final pantheon =
              skills.where((s) => s.scope == 'pantheon').toList();
          final external =
              skills.where((s) => s.scope != 'pantheon').toList();
          return RefreshIndicator(
            onRefresh: () async => _load(),
            color: P.accent,
            backgroundColor: P.surface,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
              children: [
                if (pantheon.isNotEmpty) ...[
                  const Overline('Pantheon'),
                  for (var i = 0; i < pantheon.length; i++)
                    StaggerItem(index: i, child: _card(pantheon[i])),
                ],
                if (external.isNotEmpty) ...[
                  const Overline('External'),
                  for (var i = 0; i < external.length; i++)
                    StaggerItem(
                        index: i + pantheon.length,
                        child: _card(external[i])),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _card(Skill s) {
    final busy = _busy.contains(s.name);
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
                  label: s.enabled ? 'ON' : 'OFF',
                  color: s.enabled ? P.ok : P.inkFaint,
                ),
              ],
            ),
            if (s.description != null && s.description!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(s.description!,
                  style: PT.meta, maxLines: 2, overflow: TextOverflow.ellipsis),
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
                  Expanded(
                    child: _ActionPill(
                      label: s.enabled ? 'Disable' : 'Enable',
                      color: s.enabled ? P.warn : P.ok,
                      onTap: () => _toggle(s),
                    ),
                  ),
                  if (s.scope == 'pantheon') ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ActionPill(
                        label: 'Delete',
                        color: P.err,
                        onTap: () => _delete(s),
                      ),
                    ),
                  ],
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

class _ActionPill extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionPill(
      {required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.6)),
          color: color.withValues(alpha: 0.1),
        ),
        alignment: Alignment.center,
        child: Text(label,
            style: PT.label.copyWith(fontSize: 13, color: color)),
      ),
    );
  }
}
