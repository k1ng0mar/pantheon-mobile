import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/pantheon_api.dart';
import '../theme.dart';
import '../widgets/chips.dart';
import '../widgets/forms.dart';
import '../widgets/pantheon_card.dart';
import '../widgets/states.dart';

/// Memory: browse the agent layer and add new entries.
class MemoryScreen extends StatefulWidget {
  final PantheonApi api;

  const MemoryScreen({super.key, required this.api});

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> {
  final _search = TextEditingController();
  Future<List<MemoryEntry>>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _load() {
    setState(() {
      _future = widget.api.memoryEntries(
        q: _search.text.trim().isEmpty ? null : _search.text.trim(),
      );
    });
  }

  Future<void> _add() async {
    final text = await promptText(
      context,
      title: 'Remember something',
      label: 'Memory',
      hint: 'e.g. Umar prefers concise replies',
      maxLines: 3,
      confirmLabel: 'Remember',
    );
    if (text == null || !mounted) return;
    try {
      await widget.api.addMemory(text: text);
      if (!mounted) return;
      toast(context, 'Saved to memory.');
      _load();
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Memory'),
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
        label: const Text('Remember',
            style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _load(),
              style: PT.body,
              decoration: InputDecoration(
                hintText: 'Search memory…',
                prefixIcon:  Icon(Icons.search_rounded,
                    color: P.inkFaint, weight: 1.6),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon:  Icon(Icons.clear_rounded,
                            color: P.inkFaint),
                        onPressed: () {
                          _search.clear();
                          _load();
                        },
                      ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<MemoryEntry>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return _skeleton();
                }
                if (snap.hasError) {
                  return EmptyState(
                    icon: Icons.cloud_off_outlined,
                    title: 'Couldn\'t load memory',
                    body: snap.error.toString(),
                    ctaLabel: 'Retry',
                    onCta: _load,
                  );
                }
                final entries = snap.data!;
                if (entries.isEmpty) {
                  return const EmptyState(
                    icon: Icons.psychology_outlined,
                    title: 'Nothing remembered yet',
                    body:
                        'Long-term memories Pantheon keeps about you and your work will show up here.',
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => _load(),
                  color: P.accent,
                  backgroundColor: P.surface,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                    itemCount: entries.length,
                    itemBuilder: (context, i) =>
                        StaggerItem(index: i, child: _card(entries[i])),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(MemoryEntry e) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(e.key, style: PT.mono.copyWith(fontSize: 12, color: P.ink)),
            const SizedBox(height: 6),
            Text(e.value, style: PT.small),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (e.provenanceSource != null)
                  PillChip(
                      label: 'via ${e.provenanceSource}', selected: false),
                if (e.provenanceTrust != null)
                  PillChip(label: 'trust · ${e.provenanceTrust}', selected: false),
                if (e.recordedAtMs != null)
                  Text(timeAgo(e.recordedAtMs!), style: PT.faint),
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
