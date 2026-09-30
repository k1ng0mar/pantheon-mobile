import 'package:flutter/material.dart';

import '../services/pantheon_api.dart';
import '../theme.dart';
import 'chips.dart';
import 'expert_avatar.dart';
import 'pantheon_card.dart';
import 'states.dart';

/// One headed block of a combined swarm transcript:
/// `=== Name (r_1) [status] [role] ===` + body, or a staged execution
/// log block.
class _TBlock {
  final String name;
  final String status;
  final String role;
  final String text;
  final bool isLog;

  _TBlock({
    required this.name,
    required this.status,
    required this.role,
    required this.text,
    required this.isLog,
  });
}

List<_TBlock> _parseTranscript(String text) {
  final head =
      RegExp(r'^=== (.+?) \((r_\d+)\) \[([^\]]+)\](?: \[([^\]]+)\])? ===$');
  final blocks = <_TBlock>[];
  String? name;
  String status = '';
  String role = '';
  bool isLog = false;
  final buf = StringBuffer();

  void flush() {
    if (name == null && !isLog) return;
    blocks.add(_TBlock(
      name: name ?? '',
      status: status,
      role: role,
      text: buf.toString().trim(),
      isLog: isLog,
    ));
    buf.clear();
  }

  for (final line in text.split('\n')) {
    final m = head.firstMatch(line);
    if (m != null) {
      flush();
      name = m.group(1);
      status = m.group(3) ?? '';
      role = m.group(4) ?? '';
      isLog = false;
      continue;
    }
    if (line.startsWith('=== staged execution log: ')) {
      flush();
      name = '';
      status = '';
      role = '';
      isLog = true;
      continue;
    }
    if (name != null || isLog) buf.writeln(line);
  }
  flush();
  return blocks;
}

/// @-mention chip for an expert name (the handoff visual language).
class _Mention extends StatelessWidget {
  final String name;

  const _Mention(this.name);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: P.accentSoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: P.accent.withValues(alpha: 0.4)),
      ),
      child: Text(
        '@$name',
        style: PT.label.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: P.accent,
        ),
      ),
    );
  }
}

/// One expert's message: avatar + name label (the HERMES / MEDUSA label
/// pattern), body below. The lead renders as the primary thread.
class _ExpertMessage extends StatelessWidget {
  final String name;
  final String colorHex;
  final String text;
  final bool isLead;

  const _ExpertMessage({
    required this.name,
    required this.colorHex,
    required this.text,
    required this.isLead,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isLead ? P.accentSoft : P.surface,
        borderRadius: BorderRadius.circular(P.r14),
        border: Border.all(
          color: isLead ? P.accent.withValues(alpha: 0.45) : P.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MemberAvatar(name: name, colorHex: colorHex, size: 30),
              const SizedBox(width: 8),
              Expanded(
                child: Text(name,
                    style: PT.rowTitle.copyWith(fontSize: 13.5)),
              ),
              if (isLead)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                        color: P.accent.withValues(alpha: 0.5)),
                  ),
                  child: Text('LEAD',
                      style: PT.label.copyWith(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: P.accent,
                        letterSpacing: 0.8,
                      )),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            text.isEmpty ? 'No output yet.' : text,
            style: PT.body.copyWith(
              fontSize: 13.5,
              height: 1.55,
              color: text.isEmpty ? P.inkMuted : P.ink,
            ),
          ),
        ],
      ),
    );
  }
}

/// Handoff row between stages: @-mention chips for the experts handing
/// off and the ones receiving.
class _HandoffRow extends StatelessWidget {
  final String label;
  final List<String> from;
  final List<String> to;

  const _HandoffRow({
    required this.label,
    required this.from,
    required this.to,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        runSpacing: 6,
        children: [
          Text(label, style: PT.meta.copyWith(fontSize: 11.5)),
          for (final n in from) _Mention(n),
          Icon(Icons.arrow_forward_rounded, size: 14, color: P.inkMuted),
          for (final n in to) _Mention(n),
        ],
      ),
    );
  }
}

/// Team-run view for a staged swarm: participant stack, stage progress,
/// and the multi-agent transcript with per-expert attribution.
///
/// Members' messages render as team activity here; the lead's messages
/// are the primary thread (the Chat tab — the lead's run is the only
/// user-facing run).
class TeamRunView extends StatefulWidget {
  final PantheonApi api;
  final String swarmId;

  const TeamRunView({super.key, required this.api, required this.swarmId});

  @override
  State<TeamRunView> createState() => _TeamRunViewState();
}

class _TeamRunViewState extends State<TeamRunView> {
  Map<String, dynamic>? _status;
  List<_TBlock>? _blocks;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.api.swarmStatus(widget.swarmId),
        widget.api.swarmCombinedTranscript(widget.swarmId),
      ]);
      if (!mounted) return;
      final transcript = (results[1]['transcript'] as String?) ?? '';
      setState(() {
        _status = results[0];
        _blocks = _parseTranscript(transcript);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: 4,
        itemBuilder: (_, __) => const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: Shimmer(width: double.infinity, height: 72, radius: 16),
        ),
      );
    }
    if (_error != null || _status == null) {
      return EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Couldn\'t load team run',
        body: _error ?? 'The swarm status could not be loaded.',
        ctaLabel: 'Retry',
        onCta: _load,
      );
    }
    final st = _status!;
    final staged = (st['staged'] as Map?)?.cast<String, dynamic>() ?? {};
    return RefreshIndicator(
      onRefresh: _load,
      color: P.accent,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _headerCard(st, staged),
          const SizedBox(height: 8),
          const Overline('Team transcript'),
          ..._transcriptWidgets(st, staged),
        ],
      ),
    );
  }

  Widget _headerCard(Map<String, dynamic> st, Map<String, dynamic> staged) {
    final stages = (staged['stages'] as List?) ?? [];
    final agents = (st['agents'] as List?) ?? [];
    final leadAgent = agents.cast<Map>().firstWhere(
          (a) => a['lead'] == true,
          orElse: () => <String, dynamic>{},
        );
    // Participant stack: lead first, then unique stage members.
    final names = <String>[];
    void push(String n) {
      if (n.isNotEmpty && !names.contains(n)) names.add(n);
    }
    push(leadAgent['name']?.toString() ?? '');
    for (final s in stages) {
      final members = (s as Map)['members'] as List? ?? [];
      for (final m in members) {
        push(m.toString());
      }
    }
    final topo = (staged['topology']?.toString() ?? '').replaceAll('_', ' ');
    final status = st['status']?.toString() ?? 'running';
    final escalation = staged['escalation']?.toString();
    return PCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AvatarStack(
                members: [
                  for (final n in names) (name: n, colorHex: ''),
                ],
                size: 36,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  names.join(', '),
                  style: PT.rowTitle.copyWith(fontSize: 13),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (topo.isNotEmpty)
                StatusChip(label: topo.toUpperCase(), color: P.accent),
              StatusChip(
                label: status.replaceAll('_', ' ').toUpperCase(),
                color: status == 'complete'
                    ? P.ok
                    : status == 'incomplete'
                        ? P.err
                        : P.warn,
              ),
              if (staged['topology'] == 'review_loop')
                Text(
                  'review ${staged['review_iterations'] ?? 0}/${staged['max_review_iterations'] ?? 0}',
                  style: PT.meta,
                ),
            ],
          ),
          if (stages.isNotEmpty) ...[
            const SizedBox(height: 10),
            _stagePills(staged, stages),
          ],
          if (escalation != null && escalation.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: P.err.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(P.r12),
                border: Border.all(color: P.err.withValues(alpha: 0.4)),
              ),
              child: Text(escalation,
                  style: PT.body.copyWith(fontSize: 12.5, color: P.err)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stagePills(Map<String, dynamic> staged, List stages) {
    final idx = (staged['stage_index'] as num?)?.toInt() ?? 0;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (var i = 0; i < stages.length; i++)
          Builder(builder: (_) {
            final s = stages[i] as Map;
            final done = i < idx;
            final current = i == idx;
            final color = done
                ? P.ok
                : current
                    ? P.accent
                    : P.inkMuted;
            return Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: current ? P.accentSoft : Colors.transparent,
                border: Border.all(
                    color: color.withValues(alpha: current ? 0.6 : 0.45)),
              ),
              child: Text(
                '${i + 1} · ${s['name'] ?? ''}',
                style: PT.label.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            );
          }),
      ],
    );
  }

  List<Widget> _transcriptWidgets(
      Map<String, dynamic> st, Map<String, dynamic> staged) {
    final blocks = _blocks ?? [];
    final byName = <String, _TBlock>{};
    for (final b in blocks) {
      if (!b.isLog && b.name.isNotEmpty) byName[b.name] = b;
    }
    final stages = (staged['stages'] as List?) ?? [];
    final stageIdx = (staged['stage_index'] as num?)?.toInt() ?? 0;
    final widgets = <Widget>[];
    final claimed = <String>{};

    // The lead's message is the primary thread — first.
    _TBlock? leadBlock;
    for (final b in byName.values) {
      if (b.role.toLowerCase().contains('lead')) {
        leadBlock = b;
        break;
      }
    }
    if (leadBlock != null) {
      claimed.add(leadBlock.name);
      widgets.add(_ExpertMessage(
        name: leadBlock.name,
        colorHex: '',
        text: leadBlock.text,
        isLead: true,
      ));
    }

    for (var i = 0; i < stages.length; i++) {
      final s = stages[i] as Map;
      final members =
          ((s['members'] as List?) ?? []).map((e) => e.toString()).toList();
      final shown =
          members.where((n) => byName.containsKey(n)).toList();
      if (shown.isEmpty) continue;
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 8),
        child: Row(
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: i == stageIdx ? P.accentSoft : P.tonal,
                border: Border.all(
                    color: i == stageIdx
                        ? P.accent.withValues(alpha: 0.5)
                        : P.border),
              ),
              child: Text(
                'Stage ${i + 1} · ${s['name'] ?? ''}',
                style: PT.label.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: i == stageIdx ? P.accent : P.inkSecondary,
                ),
              ),
            ),
          ],
        ),
      ));
      for (final n in shown) {
        claimed.add(n);
        final b = byName[n]!;
        widgets.add(_ExpertMessage(
          name: b.name,
          colorHex: '',
          text: b.text,
          isLead: false,
        ));
      }
      if (i + 1 < stages.length) {
        final next = stages[i + 1] as Map;
        final nextMembers =
            ((next['members'] as List?) ?? []).map((e) => e.toString()).toList();
        if (nextMembers.isNotEmpty) {
          widgets.add(_HandoffRow(
            label: 'stage ${i + 1} hands off to stage ${i + 2}',
            from: shown,
            to: nextMembers,
          ));
        }
      }
    }
    // Any unclaimed agent blocks stay visible rather than vanishing.
    for (final b in byName.values) {
      if (!claimed.contains(b.name)) {
        widgets.add(_ExpertMessage(
          name: b.name,
          colorHex: '',
          text: b.text,
          isLead: false,
        ));
      }
    }
    // The staged execution log: system rows with @-mention chips for any
    // expert named in the line.
    for (final b in blocks.where((b) => b.isLog && b.text.isNotEmpty)) {
      for (final line in b.text.split('\n')) {
        final t = line.trim();
        if (t.isEmpty) continue;
        final isEsc = t.startsWith('escalation:');
        final isReview = t.startsWith('review:');
        widgets.add(Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: isEsc
                    ? P.err
                    : isReview
                        ? P.warn
                        : P.borderStrong,
                width: 2,
              ),
            ),
          ),
          child: _logLine(t, byName.keys.toList(),
              isEsc ? P.err : (isReview ? P.ink : P.inkSecondary)),
        ));
      }
    }
    if (widgets.isEmpty) {
      widgets.add(Text('No transcript yet.', style: PT.meta));
    }
    return widgets;
  }

  /// A log line with @-mention chips for every expert named in it.
  Widget _logLine(String line, List<String> names, Color color) {
    final sorted = names.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    final spans = <InlineSpan>[];
    var rest = line;
    while (rest.isNotEmpty) {
      var earliest = -1;
      var hit = '';
      for (final n in sorted) {
        if (n.isEmpty) continue;
        final i = rest.indexOf(n);
        if (i >= 0 && (earliest < 0 || i < earliest)) {
          earliest = i;
          hit = n;
        }
      }
      if (earliest < 0) {
        spans.add(TextSpan(
            text: rest, style: PT.body.copyWith(fontSize: 12, color: color)));
        break;
      }
      if (earliest > 0) {
        spans.add(TextSpan(
            text: rest.substring(0, earliest),
            style: PT.body.copyWith(fontSize: 12, color: color)));
      }
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: _Mention(hit),
      ));
      rest = rest.substring(earliest + hit.length);
    }
    return RichText(text: TextSpan(children: spans));
  }
}
