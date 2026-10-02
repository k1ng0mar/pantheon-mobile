import 'dart:convert';

/// Machine-readable design-round artifact carried in a
/// ````drafthouse-gate` fenced block in an assistant message.
///
/// Consumer contract for the Phase 5 UI surfaces (spec:
/// `drafthouse-pantheon-plugin/docs/phase5-ui-spec.md` §1). The block is
/// emitted by the `pantheon-design-verify` skill at the end of each design
/// round; `vision` is null when L4 (vision) is off.
class DrafthouseGateBlock {
  final String artifact;
  final int round;
  final List<DrafthouseVariant> variants;
  final String judgePick;
  final Map<String, double> judgeScores;
  final DrafthouseGateReport gate;

  /// `"needs_human"` (round done, waiting on the human) or `"ship"`
  /// (all gates pass and already approved — informational only).
  final String status;

  const DrafthouseGateBlock({
    required this.artifact,
    required this.round,
    required this.variants,
    required this.judgePick,
    required this.judgeScores,
    required this.gate,
    required this.status,
  });

  /// Parse the first ````drafthouse-gate` fenced block in [text] that sits
  /// outside ordinary code fences. Returns null when there is no block or
  /// the JSON is malformed/incomplete.
  static DrafthouseGateBlock? parseFirst(String text) {
    // _fence (see MessageContent) never matches a `drafthouse-gate` fence:
    // its language-tag group is `(\w*)` and `-` is not a word char. So
    // stripping ordinary fences first proves the gate fence is not quoted
    // inside one (e.g. a contract example in a doc block). Longer
    // (````) fences go first for the same reason.
    final plain = text
        .replaceAll(_longFence, ' ')
        .replaceAll(_ordinaryFence, ' ');
    final m = _gateFence.firstMatch(plain);
    if (m == null) return null;
    try {
      final j = jsonDecode(m.group(1)!) as Map<String, dynamic>;
      return DrafthouseGateBlock.fromJson(j);
    } catch (_) {
      return null;
    }
  }

  /// Longer (````) fenced blocks, which can quote a gate fence inside them.
  static final _longFence = RegExp(r'````[\s\S]*?````');

  /// Ordinary fenced code blocks. Mirrors `MessageContent`'s private fence
  /// regex (duplicated so the model stays import-free for tests).
  static final _ordinaryFence = RegExp(r'```(\w*)\s*\n([\s\S]*?)```');

  /// The gate fence itself. Negative lookbehind/ahead keep it from matching
  /// inside longer-fenced (```` ````) blocks.
  static final _gateFence =
      RegExp(r'(?<!`)```drafthouse-gate\s*\n([\s\S]*?)```(?!`)');

  factory DrafthouseGateBlock.fromJson(Map<String, dynamic> j) {
    final variants = (j['variants'] as List)
        .map((v) => DrafthouseVariant.fromJson(v as Map<String, dynamic>))
        .toList();
    final scores = <String, double>{};
    (j['judge_scores'] as Map<String, dynamic>?)
        ?.forEach((k, v) => scores[k] = (v as num).toDouble());
    return DrafthouseGateBlock(
      artifact: j['artifact'] as String,
      round: (j['round'] as num).toInt(),
      variants: variants,
      judgePick: j['judge_pick'] as String,
      judgeScores: scores,
      gate: DrafthouseGateReport.fromJson(j['gate'] as Map<String, dynamic>),
      status: j['status'] as String,
    );
  }

  bool get needsHuman => status == 'needs_human';

  /// The judge's picked variant (falls back to the first variant when the
  /// pick id is unknown).
  DrafthouseVariant get pickedVariant => variants
      .firstWhere((v) => v.id == judgePick, orElse: () => variants.first);

  /// Index of the picked variant in [variants].
  int get pickedIndex =>
      variants.indexWhere((v) => v.id == judgePick).clamp(0, variants.length);

  /// One-line gate summary for the card, e.g.
  /// `P0=0 · 5-dim min=4 · tokens=pass · vision 8.4`.
  String gateSummary() {
    final parts = <String>[
      'P0=${gate.p0}',
      '5-dim min=${gate.fiveDimMin}',
      'tokens=${gate.tokens}',
    ];
    if (gate.visionComposite != null) {
      parts.add('vision ${gate.visionComposite!.toStringAsFixed(1)}');
    }
    return parts.join(' · ');
  }
}

class DrafthouseVariant {
  final String id;
  final String label;

  /// `POST /api/uploads` id of the round still; bytes via
  /// `GET /api/uploads/:id`.
  final String still;

  const DrafthouseVariant({
    required this.id,
    required this.label,
    required this.still,
  });

  factory DrafthouseVariant.fromJson(Map<String, dynamic> j) =>
      DrafthouseVariant(
        id: j['id'] as String,
        label: j['label'] as String,
        still: j['still'] as String,
      );

  /// Display label, e.g. `B · Strong-fit`.
  String displayLabel() => '${id.toUpperCase()} · $label';
}

class DrafthouseGateReport {
  final int p0;
  final int p1;
  final int p2;

  /// Dimension name → 1–5 score.
  final Map<String, int> fiveDim;
  final String tokens;

  /// Null when L4 vision is off.
  final double? visionComposite;
  final List<String> mustFix;

  const DrafthouseGateReport({
    required this.p0,
    required this.p1,
    required this.p2,
    required this.fiveDim,
    required this.tokens,
    this.visionComposite,
    this.mustFix = const [],
  });

  factory DrafthouseGateReport.fromJson(Map<String, dynamic> j) {
    final five = <String, int>{};
    (j['five_dim'] as Map<String, dynamic>?)
        ?.forEach((k, v) => five[k] = (v as num).toInt());
    final vision = j['vision'];
    double? composite;
    List<String> mustFix = const [];
    if (vision is Map<String, dynamic>) {
      final c = vision['composite'];
      if (c is num) composite = c.toDouble();
      final mf = vision['must_fix'];
      if (mf is List) mustFix = mf.map((e) => e.toString()).toList();
    }
    return DrafthouseGateReport(
      p0: (j['p0'] as num).toInt(),
      p1: (j['p1'] as num).toInt(),
      p2: (j['p2'] as num).toInt(),
      fiveDim: five,
      tokens: j['tokens'] as String,
      visionComposite: composite,
      mustFix: mustFix,
    );
  }

  int get fiveDimMin =>
      fiveDim.isEmpty ? 0 : fiveDim.values.reduce((a, b) => a < b ? a : b);

  String get fiveDimMinName {
    final min = fiveDimMin;
    return fiveDim.entries
        .firstWhere((e) => e.value == min, orElse: () => fiveDim.entries.first)
        .key;
  }

  bool get tokensPass => tokens.toLowerCase() == 'pass';
}

// ---------------------------------------------------------------------------
// Action payloads — the exact strings the verify skill treats as the
// approval / handoff trigger and steering directives (spec §1/§3).
// ---------------------------------------------------------------------------

/// Approve — the skill treats this exact message as the handoff trigger.
String drafthouseApproveMessage() => 'Approved — proceed to handoff.';

/// Request changes — steer/queue the running turn with the human's note
/// against a specific round + variant.
String drafthouseRequestChangesMessage(int round, String variantId, String text) =>
    'Round $round, variant $variantId: $text';

/// Pick variant — the human's pick overrides the judge's; the skill treats
/// it as a steering directive, not a gate waiver.
String drafthousePickVariantMessage(String variantId) =>
    'Use variant $variantId for the next round.';
