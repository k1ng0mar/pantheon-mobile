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
    // The dashboard returns these as arrays of {model|day, totals} objects
    // (sorted, highest cost first) — the same shape the web UI consumes.
    Map<String, UsageTotals> section(String key, String nameKey) {
      final out = <String, UsageTotals>{};
      final list = j[key];
      if (list is List) {
        for (final item in list) {
          if (item is Map) {
            final m = item.cast<String, dynamic>();
            final name = m[nameKey] as String?;
            final totals = m['totals'];
            if (name != null && totals is Map) {
              out[name] =
                  UsageTotals.fromJson(totals.cast<String, dynamic>());
            }
          }
        }
      }
      return out;
    }

    return UsageStats(
      totals: UsageTotals.fromJson(
          (j['totals'] as Map?)?.cast<String, dynamic>() ?? {}),
      byModel: section('by_model', 'model'),
      byDay: section('by_day', 'day'),
    );
  }
}
