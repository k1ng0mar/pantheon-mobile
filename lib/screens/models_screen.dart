import 'package:flutter/material.dart';

import '../models/config_doc.dart';
import '../services/pantheon_api.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/chips.dart';
import '../widgets/forms.dart';
import '../widgets/pantheon_card.dart';
import '../widgets/states.dart';

/// Models: the default `[model]` slot plus every auxiliary model slot
/// (any config table pinning provider/model). Editable in place via
/// `PUT /api/config`.
class ModelsScreen extends StatefulWidget {
  final PantheonApi api;

  const ModelsScreen({super.key, required this.api});

  @override
  State<ModelsScreen> createState() => _ModelsScreenState();
}

class _ModelsScreenState extends State<ModelsScreen> {
  Future<ConfigDoc>? _future;
  final Set<String> _busy = {};

  /// Aux slot labels for the known auxiliary kinds.
  static const _auxTitles = {
    'judge': 'Judge',
    'title_gen': 'Title generator',
    'compression': 'Compression',
    'embeddings': 'Embeddings',
    'extraction': 'Extraction',
    'rerank': 'Rerank',
    'planner': 'Planner',
    'vision': 'Vision',
    'video': 'Video analysis',
    'stt': 'Speech to text',
    'tts': 'Text to speech',
  };

  /// Config tables that are never model slots.
  static const _excluded = {
    'agents', 'mcp', 'budget', 'policy', 'nightly', 'consolidation',
    'gateway', 'tools', 'permissions', 'server',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() => _future = widget.api.getConfig());
  }

  List<ModelSlot> _slots(ConfigDoc doc) {
    final out = <ModelSlot>[];
    String? str(Map<String, dynamic> m, String k) {
      final v = m[k];
      return v is String && v.isNotEmpty ? v : null;
    }

    for (final entry in doc.values.entries) {
      final section = entry.key;
      if (entry.value is! Map) continue;
      final m = (entry.value as Map).cast<String, dynamic>();
      final provider = str(m, 'provider');
      final model = str(m, 'model');
      if (provider == null && model == null) continue;
      if (_excluded.contains(section)) continue;
      final isDefault = section == 'model';
      out.add(ModelSlot(
        section: section,
        title: isDefault
            ? 'Default'
            : (_auxTitles[section] ??
                section.replaceAll('_', ' ').toUpperCase()),
        provider: provider,
        model: model,
        apiKeyEnv: str(m, 'api_key_env'),
      ));
    }
    out.sort((a, b) {
      if (a.section == 'model') return -1;
      if (b.section == 'model') return 1;
      return a.section.compareTo(b.section);
    });
    return out;
  }

  Future<void> _edit(ModelSlot slot) async {
    final providerCtrl = TextEditingController(text: slot.provider ?? '');
    final modelCtrl = TextEditingController(text: slot.model ?? '');
    try {
      final saved = await showPSheet<bool>(
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
                  Text('Edit ${slot.title}', style: PT.sectionTitle),
                  const SizedBox(height: 4),
                  Text('[${slot.section}] in config.toml', style: PT.monoSm),
                  const SizedBox(height: 16),
                  TextField(
                    controller: providerCtrl,
                    style: PT.body,
                    decoration: const InputDecoration(
                      labelText: 'Provider',
                      hintText: 'e.g. anthropic, openai, groq',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: modelCtrl,
                    style: PT.body,
                    decoration: const InputDecoration(
                      labelText: 'Model',
                      hintText: 'e.g. claude-opus-4-6',
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
                          label: 'Save',
                          onTap: () async {
                            final changes = <String, dynamic>{
                              '${slot.section}.provider':
                                  providerCtrl.text.trim(),
                              '${slot.section}.model': modelCtrl.text.trim(),
                            };
                            try {
                              await widget.api.putConfig(changes);
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
      if (saved == true && mounted) {
        toast(context, '${slot.title} model updated.');
        _load();
      }
    } finally {
      providerCtrl.dispose();
      modelCtrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Models'),
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
          final slots = _slots(snap.data!);
          if (slots.isEmpty) {
            return const EmptyState(
              icon: Icons.smart_toy_outlined,
              title: 'No model slots found',
              body: 'Run `pantheon setup` on the runtime to configure a model.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => _load(),
            color: P.accent,
            backgroundColor: P.surface,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                const Overline('Default'),
                for (final s in slots.where((s) => s.section == 'model'))
                  _slotCard(s),
                const Overline('Auxiliary'),
                for (final s in slots.where((s) => s.section != 'model'))
                  _slotCard(s),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 16, 4, 0),
                  child: Text(
                    'Auxiliary slots inherit the default provider when left blank.',
                    style: PT.meta.copyWith(color: P.inkFaint),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _slotCard(ModelSlot s) {
    final busy = _busy.contains(s.section);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PCard(
        onTap: busy ? null : () => _edit(s),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: P.accentSoft,
                borderRadius: BorderRadius.circular(P.r14),
              ),
              child: Icon(
                s.section == 'model'
                    ? Icons.smart_toy_outlined
                    : Icons.psychology_outlined,
                color: P.accent,
                size: 22,
                weight: 1.6,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.title, style: PT.rowTitle),
                  const SizedBox(height: 3),
                  Text(
                    [
                      if (s.provider != null) s.provider!,
                      if (s.model != null) s.model!,
                    ].join(' · ').ifEmpty('inherits default'),
                    style: PT.monoSm,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (s.apiKeyEnv != null) ...[
                    const SizedBox(height: 2),
                    Text('key · ${s.apiKeyEnv}',
                        style: PT.faint.copyWith(fontSize: 10)),
                  ],
                ],
              ),
            ),
             Icon(Icons.chevron_right_rounded,
                color: P.inkFaint, size: 22),
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
        child: Shimmer(width: double.infinity, height: 72, radius: 16),
      ),
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
