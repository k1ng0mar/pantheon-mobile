/// One memory record from `GET /api/memory`.
/// Shape: {"namespace": "…", "records": [{"key","value","layer",
/// "namespace","provenance":{"source","origin","trust"}|null,
/// "recorded_at_ms","score"}]}
class MemoryEntry {
  final String key;
  final String value;
  final int? recordedAtMs;
  final String? provenanceSource;
  final String? provenanceTrust;

  MemoryEntry({
    required this.key,
    required this.value,
    this.recordedAtMs,
    this.provenanceSource,
    this.provenanceTrust,
  });

  factory MemoryEntry.fromJson(Map<String, dynamic> j) {
    final prov = j['provenance'] is Map
        ? (j['provenance'] as Map).cast<String, dynamic>()
        : null;
    return MemoryEntry(
      key: j['key'] as String? ?? '',
      value: j['value'] as String? ?? '',
      recordedAtMs: (j['recorded_at_ms'] as num?)?.toInt(),
      provenanceSource: prov?['source'] as String?,
      provenanceTrust: prov?['trust'] as String?,
    );
  }
}
