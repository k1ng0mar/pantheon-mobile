import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/pantheon_api.dart';
import '../theme.dart';
import '../widgets/forms.dart';
import '../widgets/pantheon_card.dart';
import '../widgets/states.dart';

/// Agent profiles: the `[agents]` table of the runtime config.
/// Read-only list with a detail sheet; edits go through Configs.
class ProfilesScreen extends StatefulWidget {
  final PantheonApi api;

  const ProfilesScreen({super.key, required this.api});

  @override
  State<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends State<ProfilesScreen> {
  Future<ConfigDoc>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() => _future = widget.api.getConfig());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profiles'),
        actions: [
          IconButton(
            icon:  Icon(Icons.refresh_rounded,
                color: P.inkSecondary, weight: 1.6),
            onPressed: _load,
          ),
        ],
      ),
      body: FutureBuilder<ConfigDoc>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return _skeleton();
          }
          if (snap.hasError) {
            return EmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'Couldn\'t load config',
              body: snap.error.toString(),
              ctaLabel: 'Retry',
              onCta: _load,
            );
          }
          final agents = snap.data!.agents;
          if (agents.isEmpty) {
            return const EmptyState(
              icon: Icons.person_outline_rounded,
              title: 'No profiles declared',
              body:
                  'This install has no [agents] table in its config yet. '
                  'Add one under Configs to give Pantheon a named identity.',
            );
          }
          final names = agents.keys.toList()..sort();
          return RefreshIndicator(
            onRefresh: () async => _load(),
            color: P.accent,
            backgroundColor: P.surface,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              itemCount: names.length,
              itemBuilder: (context, i) {
                final name = names[i];
                return StaggerItem(
                    index: i,
                    child: _profileCard(
                        name, agents[name] ?? {}));
              },
            ),
          );
        },
      ),
    );
  }

  Widget _profileCard(String name, Map<String, dynamic> p) {
    final display = p['display_name'] as String?;
    final inherits = p['inherits'] as String?;
    final policy = p['policy'] as String?;
    final model = p['model'] as String?;
    final memoryNs = p['memory_namespace'] as String?;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PCard(
        onTap: () => _detail(name, p),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                gradient: P.gradient,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                name.isEmpty ? '?' : name[0].toUpperCase(),
                style: const TextStyle(
                    fontFamily: PT.displayFamily,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.white),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(display?.isNotEmpty == true ? display! : name,
                      style: PT.rowTitle),
                  const SizedBox(height: 3),
                  Text(
                    [
                      if (policy != null) 'policy · $policy',
                      if (model != null) 'model · $model',
                      if (inherits != null) 'inherits · $inherits',
                    ].join('   ').ifEmpty('agent profile'),
                    style: PT.meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (memoryNs != null) ...[
                    const SizedBox(height: 2),
                    Text('memory · $memoryNs',
                        style: PT.monoSm.copyWith(fontSize: 10)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _detail(String name, Map<String, dynamic> p) async {
    await showPSheet(
      context,
      SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SheetHandle(),
              const SizedBox(height: 8),
              Text(name, style: PT.sectionTitle),
              const SizedBox(height: 4),
               Text('AGENT PROFILE', style: PT.overline),
              const SizedBox(height: 16),
              KvRow('display name', p['display_name']?.toString() ?? '—'),
              KvRow('inherits', p['inherits']?.toString() ?? '—'),
              KvRow('policy', p['policy']?.toString() ?? '—'),
              KvRow('model', p['model']?.toString() ?? 'runtime default'),
              KvRow('memory namespace',
                  p['memory_namespace']?.toString() ?? '—',
                  mono: true),
              KvRow('persona file', p['soul_file']?.toString() ?? '—',
                  mono: true),
              KvRow('instructions file',
                  p['agents_file']?.toString() ?? '—',
                  mono: true),
              const SizedBox(height: 8),
              Text(
                'Edit profiles under Configs → [agents].',
                style: PT.meta.copyWith(color: P.inkFaint),
              ),
            ],
          ),
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
        child: Shimmer(width: double.infinity, height: 76, radius: 16),
      ),
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
