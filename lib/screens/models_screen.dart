import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/models.dart';
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

  /// In-flight slider position for `compression.target_percent` while the
  /// user drags. Null = show the server value from the ConfigDoc.
  double? _compressionDraft;

  /// In-flight values for the `[swarm]` knobs while a save is pending.
  /// Null entries = show the server value from the ConfigDoc (or the
  /// documented default when the section is absent).
  final Map<String, dynamic> _swarmDraft = {};

  /// In-flight value for the `[budget]` child-budget knob while a save
  /// is pending. Null = show the server value from the ConfigDoc; an
  /// absent key means no cap is configured.
  int? _childBudgetDraft;
  final _childBudgetCtrl = TextEditingController();
  final _childBudgetFocus = FocusNode();

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

  @override
  void dispose() {
    _childBudgetCtrl.dispose();
    _childBudgetFocus.dispose();
    super.dispose();
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
    setState(() => _busy.add(slot.section));
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
      if (mounted) setState(() => _busy.remove(slot.section));
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
                  _slotCard(s, snap.data!),
                const Overline('Auxiliary'),
                for (final s in slots.where((s) => s.section != 'model'))
                  _slotCard(s, snap.data!),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 16, 4, 0),
                  child: Text(
                    'Auxiliary slots inherit the default provider when left blank.',
                    style: PT.meta.copyWith(color: P.inkFaint),
                  ),
                ),
                const Overline('Swarm'),
                _swarmCard(snap.data!),
                const Overline('Budget'),
                _budgetCard(snap.data!),
              ],
            ),
          );
        },
      ),
    );
  }

  /// The `[swarm]` coordination knobs: caps for subagent count, spawn
  /// depth, and concurrency, plus whether agents may spawn children.
  /// Saved on change via `PUT /api/config`; the section may be absent
  /// (fresh config), in which case the documented defaults show.
  Widget _swarmCard(ConfigDoc doc) {
    final section = doc.values['swarm'];
    final raw = section is Map ? section.cast<String, dynamic>() : {};
    int intVal(String key, int fallback) {
      if (_swarmDraft[key] is int) return _swarmDraft[key] as int;
      final v = raw[key];
      return v is num ? v.toInt() : fallback;
    }

    bool boolVal(String key, bool fallback) {
      if (_swarmDraft[key] is bool) return _swarmDraft[key] as bool;
      final v = raw[key];
      return v is bool ? v : fallback;
    }

    Widget stepperRow(String key, String label, String caption, int value,
        int min, int max) {
      final busy = _busy.contains(key);
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: PT.rowTitle),
                  const SizedBox(height: 2),
                  Text(caption,
                      style: PT.meta.copyWith(color: P.inkFaint)),
                ],
              ),
            ),
            PStepper(
              value: value,
              min: min,
              max: max,
              onChanged: busy ? null : (v) => _saveSwarm(key, v),
            ),
          ],
        ),
      );
    }

    final spawnKey = 'swarm.allow_child_spawn';
    final spawnBusy = _busy.contains(spawnKey);
    final spawn = boolVal('allow_child_spawn', true);
    return PCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          stepperRow('swarm.max_subagents', 'Max subagents',
              'Hard cap on subagents in one swarm.', intVal('max_subagents', 4), 1, 16),
          stepperRow('swarm.max_depth', 'Max depth',
              'How deep subagents may nest.', intVal('max_depth', 2), 1, 5),
          stepperRow('swarm.max_concurrent', 'Max concurrent',
              'How many run at once.', intVal('max_concurrent', 4), 1, 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Allow child spawn', style: PT.rowTitle),
                    const SizedBox(height: 2),
                    Text('Subagents may spawn their own helpers.',
                        style: PT.meta.copyWith(color: P.inkFaint)),
                  ],
                ),
              ),
              Switch(
                value: spawn,
                activeTrackColor: P.accent,
                onChanged: spawnBusy ? null : (v) => _saveSwarm(spawnKey, v),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Save one `[swarm]` knob on change. The draft keeps the UI stable
  /// while the save is in flight; it is cleared on failure so the row
  /// snaps back to the server value.
  Future<void> _saveSwarm(String key, dynamic value) async {
    if (_busy.contains(key)) return;
    final short = key.substring('swarm.'.length);
    setState(() {
      _busy.add(key);
      _swarmDraft[short] = value;
    });
    try {
      await widget.api.putConfig({key: value});
    } catch (e) {
      setState(() => _swarmDraft.remove(short));
      if (mounted) toastError(context, e);
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  /// The `[budget]` child-budget knob: the default max tokens for a
  /// delegated child's generation. A numeric input, saved on submit via
  /// `PUT /api/config`; an absent key means no cap is configured.
  Widget _budgetCard(ConfigDoc doc) {
    final section = doc.values['budget'];
    final raw = section is Map ? section.cast<String, dynamic>() : {};
    int? serverVal;
    final v = raw['delegate_child_max_tokens'];
    if (v is num) serverVal = v.toInt();
    final display = _childBudgetDraft ?? serverVal;
    final text = display?.toString() ?? '';
    if (!_childBudgetFocus.hasFocus && _childBudgetCtrl.text != text) {
      _childBudgetCtrl.text = text;
    }

    const key = 'budget.delegate_child_max_tokens';
    final busy = _busy.contains(key);
    return PCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Default child budget (max tokens)', style: PT.rowTitle),
                const SizedBox(height: 2),
                Text("Default max tokens for a delegated child's generation.",
                    style: PT.meta.copyWith(color: P.inkFaint)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 110,
            child: TextField(
              controller: _childBudgetCtrl,
              focusNode: _childBudgetFocus,
              enabled: !busy,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textAlign: TextAlign.right,
              style: PT.mono,
              decoration: const InputDecoration(hintText: 'unset'),
              onSubmitted: (_) => _submitBudget(),
            ),
          ),
        ],
      ),
    );
  }

  /// Parse the child-budget input and save it. Empty = leave unchanged;
  /// a non-positive or unparseable value snaps back to the server value.
  void _submitBudget() {
    final text = _childBudgetCtrl.text.trim();
    if (text.isEmpty) {
      _childBudgetFocus.unfocus();
      toast(context, 'No value entered — budget unchanged.');
      return;
    }
    final value = int.tryParse(text);
    if (value == null || value < 1) {
      toastError(context, 'Enter a positive number of tokens.');
      setState(() => _childBudgetDraft = null);
      _childBudgetFocus.unfocus();
      return;
    }
    _saveBudget('budget.delegate_child_max_tokens', value);
  }

  /// Save the `[budget]` child-budget knob. The draft keeps the UI stable
  /// while the save is in flight; it is cleared on failure so the row
  /// snaps back to the server value.
  Future<void> _saveBudget(String key, int value) async {
    if (_busy.contains(key)) return;
    setState(() {
      _busy.add(key);
      _childBudgetDraft = value;
    });
    _childBudgetFocus.unfocus();
    try {
      await widget.api.putConfig({key: value});
      if (mounted) toast(context, 'Child budget saved.');
    } catch (e) {
      setState(() => _childBudgetDraft = null);
      if (mounted) toastError(context, e);
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  Widget _slotCard(ModelSlot s, ConfigDoc doc) {
    final busy = _busy.contains(s.section);
    // The compression card carries its own slider: the edit sheet opens
    // from the header row only, so slider taps/drags never trigger it.
    final isCompression = s.section == 'compression';
    final header = Row(
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
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PCard(
        onTap: (busy || isCompression) ? null : () => _edit(s),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isCompression)
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: busy ? null : () => _edit(s),
                  borderRadius: BorderRadius.circular(P.r12),
                  splashColor: P.accentSoft,
                  highlightColor: P.accentSoft,
                  child: header,
                ),
              )
            else
              header,
            if (isCompression) _compressionControl(doc),
          ],
        ),
      ),
    );
  }

  /// Percentage control for `compression.target_percent`: the summary
  /// target size as a percentage of the absorbed transcript chars.
  /// Higher keeps more detail; lower compresses harder.
  Widget _compressionControl(ConfigDoc doc) {
    final section = doc.values['compression'];
    final raw = section is Map ? section['target_percent'] : null;
    final current = raw is int ? raw.clamp(1, 100) : 12;
    final pct = _compressionDraft ?? current.toDouble();
    final busy = _busy.contains('compression.target_percent');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text('Summary size: ${pct.round()}% of compressed material',
            style: PT.label),
        Slider(
          value: pct,
          min: 1,
          max: 100,
          divisions: 99,
          activeColor: P.accent,
          inactiveColor: P.tonal,
          label: '${pct.round()}%',
          onChanged: busy ? null : (v) => setState(() => _compressionDraft = v),
          onChangeEnd: (v) => _saveCompressionPct(v.round()),
        ),
        Text('Higher keeps more detail; lower compresses harder.',
            style: PT.meta.copyWith(color: P.inkFaint)),
      ],
    );
  }

  Future<void> _saveCompressionPct(int pct) async {
    const key = 'compression.target_percent';
    if (_busy.contains(key)) return;
    setState(() {
      _busy.add(key);
      // Snap back to the server value; _load() refreshes it on success.
      _compressionDraft = null;
    });
    try {
      await widget.api.putConfig({key: pct});
      _load();
    } catch (e) {
      if (mounted) toastError(context, e);
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
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
