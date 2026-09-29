/// Config document from `GET /api/config`:
/// {"path": "…", "values": {…}, "raw": "…toml…"}.
class ConfigDoc {
  final String path;
  final Map<String, dynamic> values;
  final String raw;

  ConfigDoc({required this.path, required this.values, required this.raw});

  factory ConfigDoc.fromJson(Map<String, dynamic> j) => ConfigDoc(
        path: j['path'] as String? ?? '',
        values: j['values'] is Map
            ? (j['values'] as Map).cast<String, dynamic>()
            : {},
        raw: j['raw'] as String? ?? '',
      );

  /// The `[agents]` table: agent profile declarations, name -> fields.
  Map<String, Map<String, dynamic>> get agents {
    final a = values['agents'];
    if (a is! Map) return {};
    return a.map((k, v) => MapEntry(
        k.toString(),
        v is Map ? (v as Map).cast<String, dynamic>() : <String, dynamic>{}));
  }
}

/// One flattened schema field from `GET /api/config/schema`:
/// {"path": "model.provider", "type": "string", "value": …, "enum"?}.
class ConfigField {
  final String path;
  final String type;
  final dynamic value;
  final List<String>? enumValues;

  ConfigField(
      {required this.path,
      required this.type,
      this.value,
      this.enumValues});

  factory ConfigField.fromJson(Map<String, dynamic> j) => ConfigField(
        path: j['path'] as String? ?? '',
        type: j['type'] as String? ?? 'unknown',
        value: j['value'],
        enumValues: (j['enum'] as List?)
            ?.map((e) => e.toString())
            .toList(),
      );
}

/// A model slot: the default `[model]` table or an auxiliary table
/// (`[judge]`, `[embeddings]`, …) that pins provider/model.
class ModelSlot {
  final String section; // e.g. "model", "judge"
  final String title; // display label
  final String? provider;
  final String? model;
  final String? apiKeyEnv;

  ModelSlot({
    required this.section,
    required this.title,
    this.provider,
    this.model,
    this.apiKeyEnv,
  });
}
