class UsageTotals {
  final int calls;
  final int inputTokens;
  final int outputTokens;
  final int totalTokens;
  final double costUsd;

  UsageTotals({
    required this.calls,
    required this.inputTokens,
    required this.outputTokens,
    required this.totalTokens,
    required this.costUsd,
  });

  factory UsageTotals.fromJson(Map<String, dynamic> j) => UsageTotals(
        calls: (j['calls'] as num?)?.toInt() ?? 0,
        inputTokens: (j['input_tokens'] as num?)?.toInt() ?? 0,
        outputTokens: (j['output_tokens'] as num?)?.toInt() ?? 0,
        totalTokens: (j['total_tokens'] as num?)?.toInt() ?? 0,
        costUsd: (j['cost_usd'] as num?)?.toDouble() ?? 0,
      );
}

class UsageStats {
  final UsageTotals totals;
  final Map<String, UsageTotals> byModel;
  final Map<String, UsageTotals> byDay;

  UsageStats(
      {required this.totals, required this.byModel, required this.byDay});

  factory UsageStats.fromJson(Map<String, dynamic> j) {
    Map<String, UsageTotals> section(String key) {
      final m = (j[key] as Map?)?.cast<String, dynamic>() ?? {};
      return m.map((k, v) => MapEntry(
          k, UsageTotals.fromJson((v as Map).cast<String, dynamic>())));
    }

    return UsageStats(
      totals: UsageTotals.fromJson(
          (j['totals'] as Map?)?.cast<String, dynamic>() ?? {}),
      byModel: section('by_model'),
      byDay: section('by_day'),
    );
  }
}
