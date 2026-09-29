import 'package:flutter/material.dart';

import '../models/log_tail.dart';
import '../services/pantheon_api.dart';
import '../theme.dart';
import '../widgets/chips.dart';
import '../widgets/forms.dart';
import '../widgets/states.dart';

/// Logs: tail viewer for the runtime logs (agent / errors / gateway),
/// with level + grep filters.
class LogsScreen extends StatefulWidget {
  final PantheonApi api;

  const LogsScreen({super.key, required this.api});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  static const _sources = ['agent', 'errors', 'gateway'];
  static const _levels = [null, 'debug', 'info', 'warning', 'error'];

  String _source = 'agent';
  String? _level;
  final _grep = TextEditingController();
  Future<LogTail>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _grep.dispose();
    super.dispose();
  }

  void _load() {
    setState(() {
      _future = widget.api.logs(
        source: _source,
        tail: 200,
        level: _level,
        grep: _grep.text.trim().isEmpty ? null : _grep.text.trim(),
      );
    });
  }

  Color _levelColor(String line) {
    final l = line.toUpperCase();
    if (l.contains('ERROR')) return P.err;
    if (l.contains('WARN')) return P.warn;
    if (l.contains('DEBUG')) return P.inkFaint;
    return P.info;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Logs'),
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
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                for (final s in _sources)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: PillChip(
                      label: s,
                      selected: _source == s,
                      onTap: () {
                        setState(() => _source = s);
                        _load();
                      },
                    ),
                  ),
                Container(
                    width: 1, height: 24, color: P.border, margin: const EdgeInsets.symmetric(horizontal: 4)),
                for (final l in _levels)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: PillChip(
                      label: l ?? 'all',
                      selected: _level == l,
                      onTap: () {
                        setState(() => _level = l);
                        _load();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _grep,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _load(),
              onChanged: (_) => setState(() {}),
              style: PT.mono.copyWith(color: P.ink),
              decoration: InputDecoration(
                hintText: 'grep…',
                prefixIcon:  Icon(Icons.search_rounded,
                    color: P.inkFaint, weight: 1.6),
                suffixIcon: _grep.text.isEmpty
                    ? null
                    : IconButton(
                        icon:  Icon(Icons.clear_rounded,
                            color: P.inkFaint),
                        onPressed: () {
                          _grep.clear();
                          _load();
                        },
                      ),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<LogTail>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return _skeleton();
                }
                if (snap.hasError) {
                  return EmptyState(
                    icon: Icons.cloud_off_outlined,
                    title: 'Couldn\'t load logs',
                    body: snap.error.toString(),
                    ctaLabel: 'Retry',
                    onCta: _load,
                  );
                }
                final tail = snap.data!;
                if (tail.lines.isEmpty) {
                  return EmptyState(
                    icon: Icons.terminal_rounded,
                    title: 'No log lines',
                    body: tail.note ??
                        'Nothing in $_source.log matches right now.',
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => _load(),
                  color: P.accent,
                  backgroundColor: P.surface,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: tail.lines.length,
                    itemBuilder: (context, i) {
                      final line = tail.lines[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              margin: const EdgeInsets.only(top: 5),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _levelColor(line),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: SelectableText(
                                line,
                                style: PT.mono.copyWith(fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _skeleton() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: 12,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Shimmer(
            width: double.infinity,
            height: 14,
            radius: 4),
      ),
    );
  }
}
