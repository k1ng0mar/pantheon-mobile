import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/pantheon_api.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/chips.dart';
import '../widgets/forms.dart';
import '../widgets/pantheon_card.dart';
import '../widgets/states.dart';

/// Keys: the runtime `.env` key manager. Values are redacted server-side —
/// the app only ever shows the masked form, never the secret itself.
class KeysScreen extends StatefulWidget {
  final PantheonApi api;

  const KeysScreen({super.key, required this.api});

  @override
  State<KeysScreen> createState() => _KeysScreenState();
}

class _KeysScreenState extends State<KeysScreen> {
  Future<List<EnvKey>>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() => _future = widget.api.envKeys());
  }

  Future<void> _add() async {
    final key = await promptText(
      context,
      title: 'Add key',
      label: 'Key name',
      hint: 'e.g. OPENAI_API_KEY',
      confirmLabel: 'Next',
    );
    if (key == null || !mounted) return;
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(key)) {
      toast(context, 'Key names must look like ENV_VAR names.');
      return;
    }
    final value = await promptText(
      context,
      title: 'Value for $key',
      label: 'Value',
      hint: 'Paste the secret — it is stored, never shown',
      obscure: true,
      confirmLabel: 'Save',
    );
    if (value == null || !mounted) return;
    final ok = await confirmAction(
      context,
      title: 'Save this key?',
      body: '“$key” will be written to the runtime .env file.',
      confirmLabel: 'Save',
    );
    if (!ok || !mounted) return;
    try {
      await widget.api.putEnv(key, value);
      if (!mounted) return;
      toast(context, 'Key saved.');
      _load();
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  Future<void> _delete(EnvKey k) async {
    final ok = await confirmAction(
      context,
      title: 'Delete this key?',
      body: '“${k.key}” will be removed from the runtime .env file.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await widget.api.deleteEnv(k.key);
      if (!mounted) return;
      toast(context, 'Key deleted.');
      _load();
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Keys'),
        actions: [
          IconButton(
            icon:  Icon(Icons.refresh_rounded,
                color: P.inkSecondary, weight: 1.6),
            onPressed: _load,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        backgroundColor: P.accentDeep,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded, weight: 2),
        label:
            const Text('Add', style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: FutureBuilder<List<EnvKey>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return _skeleton();
          }
          if (snap.hasError) {
            return EmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'Couldn\'t load keys',
              body: snap.error.toString(),
              ctaLabel: 'Retry',
              onCta: _load,
            );
          }
          final keys = snap.data!;
          if (keys.isEmpty) {
            return const EmptyState(
              icon: Icons.key_outlined,
              title: 'No keys stored',
              body: 'API keys for providers live in the runtime .env file. '
                  'Add the first one below.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => _load(),
            color: P.accent,
            backgroundColor: P.surface,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
              itemCount: keys.length,
              itemBuilder: (context, i) =>
                  StaggerItem(index: i, child: _card(keys[i])),
            ),
          );
        },
      ),
    );
  }

  Widget _card(EnvKey k) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(k.key,
                      style: PT.mono.copyWith(color: P.ink, fontSize: 13)),
                ),
                if (k.shadowedByProcessEnv)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child:
                        StatusChip(label: 'SHADOWED', color: P.warn),
                  ),
                Text(k.redacted,
                    style: PT.mono.copyWith(color: P.inkFaint)),
              ],
            ),
            if (k.usedBy.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: k.usedBy
                    .map((u) => PillChip(label: u, selected: false))
                    .toList(),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: PillButton(
                    label: 'Delete',
                    filled: false,
                    color: P.err,
                    onTap: () => _delete(k),
                  ),
                ),
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
        child: Shimmer(width: double.infinity, height: 90, radius: 16),
      ),
    );
  }
}
