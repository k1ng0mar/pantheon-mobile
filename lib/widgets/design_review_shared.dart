import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/drafthouse_gate.dart';
import '../services/pantheon_api.dart';
import '../theme.dart';
import 'states.dart';

/// Memoized still bytes for design rounds: `GET /api/uploads/:id`,
/// cached per session so card rebuilds and the viewer never refetch.
///
/// In-memory: upload id -> in-flight or completed byte fetch. Failures
/// are cached as null so a dead still does not get retried on every
/// rebuild. Bounded to avoid unbounded growth in long sessions — the
/// same pattern as `LinkPreviewCard._cache`.
class DesignStillCache {
  static final Map<String, Future<Uint8List?>> _cache = {};
  static const _maxCacheEntries = 100;

  static Future<Uint8List?> stillBytes(PantheonApi api, String uploadId) {
    var future = _cache[uploadId];
    if (future == null) {
      if (_cache.length >= _maxCacheEntries) {
        _cache.remove(_cache.keys.first);
      }
      future = api
          .downloadUpload(uploadId)
          .then<Uint8List?>((bytes) => Uint8List.fromList(bytes))
          .catchError((_) => null);
      _cache[uploadId] = future;
    }
    return future;
  }

  /// For tests: drop all cached stills.
  @visibleForTesting
  static void clearCacheForTest() => _cache.clear();
}

/// Status pill shared by the artifact card and the viewer: amber [P.warn]
/// "needs review" / green [P.ok] "ship".
class DesignStatusPill extends StatelessWidget {
  final bool needsHuman;

  const DesignStatusPill({super.key, required this.needsHuman});

  @override
  Widget build(BuildContext context) {
    final color = needsHuman ? P.warn : P.ok;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        needsHuman ? 'needs review' : 'ship',
        style: PT.meta.copyWith(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Gate report bottom sheet — same sheet pattern as [showTaskSheet]:
/// `showModalBottomSheet` + `DraggableScrollableSheet`, [P.surface],
/// top radius 20.
Future<void> showDesignGateSheet(
  BuildContext context, {
  required DrafthouseGateBlock block,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: P.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scrollController) => _GateReportSheet(
        block: block,
        scrollController: scrollController,
      ),
    ),
  );
}

class _GateReportSheet extends StatelessWidget {
  final DrafthouseGateBlock block;
  final ScrollController scrollController;

  const _GateReportSheet({required this.block, required this.scrollController});

  @override
  Widget build(BuildContext context) {
    final gate = block.gate;
    return SafeArea(
      child: ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          const SheetHandle(),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Gate report · round ${block.round}',
                  style: PT.sectionTitle.copyWith(color: P.ink),
                ),
              ),
              DesignStatusPill(needsHuman: block.needsHuman),
            ],
          ),
          const SizedBox(height: 16),
          Text('5-dimension scores',
              style: PT.overline.copyWith(color: P.inkSecondary)),
          const SizedBox(height: 8),
          ...gate.fiveDim.entries.map((e) => _DimRow(
                name: e.key,
                score: e.value,
                isMin: e.value == gate.fiveDimMin && gate.fiveDim.isNotEmpty,
              )),
          const SizedBox(height: 16),
          _CountRow(
              label: 'P0 blocking',
              value: '${gate.p0}',
              tone: gate.p0 > 0 ? P.err : P.ink),
          _CountRow(label: 'P1', value: '${gate.p1}', tone: P.ink),
          _CountRow(label: 'P2', value: '${gate.p2}', tone: P.ink),
          const SizedBox(height: 8),
          _CountRow(
            label: 'Tokens',
            value: gate.tokens,
            tone: gate.tokensPass ? P.ok : P.err,
          ),
          if (gate.visionComposite != null) ...[
            const SizedBox(height: 8),
            _CountRow(
              label: 'Vision composite',
              value: gate.visionComposite!.toStringAsFixed(1),
              tone: P.ink,
            ),
          ],
          if (gate.mustFix.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('MUST_FIX (${gate.mustFix.length})',
                style: PT.overline.copyWith(color: P.err)),
            const SizedBox(height: 8),
            ...gate.mustFix.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.priority_high_rounded,
                          size: 14, color: P.err),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(item,
                            style: PT.small.copyWith(color: P.ink)),
                      ),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }
}

class _DimRow extends StatelessWidget {
  final String name;
  final int score;
  final bool isMin;

  const _DimRow({required this.name, required this.score, required this.isMin});

  @override
  Widget build(BuildContext context) {
    final dot = score >= 4 ? P.ok : (score >= 3 ? P.warn : P.err);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              '${_title(name)}${isMin ? ' · min' : ''}',
              style: PT.small.copyWith(
                color: isMin ? P.warn : P.inkSecondary,
                fontWeight: isMin ? FontWeight.w600 : null,
              ),
            ),
          ),
          ...List.generate(5, (i) {
            final filled = i < score.clamp(0, 5);
            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: filled ? dot : Colors.transparent,
                  border: Border.all(
                    color: filled ? dot : P.border,
                    width: 1.5,
                  ),
                ),
              ),
            );
          }),
          const SizedBox(width: 4),
          Text('$score / 5', style: PT.meta.copyWith(color: P.inkMuted)),
        ],
      ),
    );
  }

  static String _title(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class _CountRow extends StatelessWidget {
  final String label;
  final String value;
  final Color tone;

  const _CountRow({required this.label, required this.value, required this.tone});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
              child: Text(label,
                  style: PT.small.copyWith(color: P.inkSecondary))),
          Text(value,
              style: PT.body.copyWith(
                  color: tone, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
