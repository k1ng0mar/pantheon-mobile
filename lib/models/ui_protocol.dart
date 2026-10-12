// Agent-native UI protocol (v1) models.
//
// Mirrors `pantheon-api/src/ui.rs` in the Pantheon repository. Documents
// arrive on run transcript items as `{type: 'ui', ui_id, revision,
// document}` where `document` is the serialized `UiDocument` below.
//
// Wire notes (from the Rust definitions):
// - `UiNode` flattens its component: JSON is `{id, type, ...fields}`.
// - `Component` is internally tagged on `type` (snake_case).
// - `FieldType` is tagged on `type` (snake_case).
// - `ActionKind` is tagged on `kind` (snake_case).
// - Simple enums (`ApprovalDecision`, `LayoutKind`, `ChartType`,
//   `TaskState`, `DiffLineKind`) are lowercase strings.
//
// Version policy: this client speaks v1 only. Documents with any other
// version degrade to an explanatory note (mirrors `degrade_for` in the
// Rust protocol) — a newer version is never assumed compatible.
//
// Parsing is total: missing, malformed, or unknown data degrades to a
// fallback component instead of throwing, so a bad document can never
// crash the chat screen.

/// The protocol version this client implements.
const int uiProtocolVersion = 1;

/// A versioned UI document: `{version, id, root}`.
class UiDocument {
  final int version;
  final String id;
  final UiNode root;

  UiDocument({required this.version, required this.id, required this.root});

  /// True when this client can render the document natively.
  bool get isSupported => version == uiProtocolVersion;

  factory UiDocument.fromJson(Map<String, dynamic> j) {
    final v = j['version'];
    final version = v is num ? v.toInt() : -1;
    return UiDocument(
      version: version,
      id: j['id'] is String ? j['id'] as String : '',
      root: UiNode.fromJson((j['root'] as Map?)?.cast<String, dynamic>() ?? {}),
    );
  }

  /// Explanatory fallback for unsupported versions (mirrors `degrade_for`).
  factory UiDocument.unsupportedVersion(String id, int got) => UiDocument(
        version: uiProtocolVersion,
        id: id,
        root: UiNode(
          id: '$id-fallback',
          component: UiMarkdown(
            text:
                'This content needs UI protocol v$got (this client speaks v$uiProtocolVersion).',
          ),
        ),
      );
}

/// Maximum nesting depth (root = 0). Mirrors the Rust MAX_DEPTH bound;
/// deeper input degrades to [UiUnsupported] instead of risking stack
/// overflow. The server validates this too, but the client must not
/// trust the transport.
const int _maxUiDepth = 8;

/// One addressable node: `{id, type, ...component fields}` (flattened).
class UiNode {
  final String id;
  final UiComponent component;

  UiNode({required this.id, required this.component});

  factory UiNode.fromJson(Map<String, dynamic> j) =>
      UiNode._fromJson(j, 0);

  factory UiNode._fromJson(Map<String, dynamic> j, int depth) {
    final idVal = j['id'];
    final id = idVal is String ? idVal : '';
    if (depth > _maxUiDepth) {
      return UiNode(id: id, component: UiUnsupported(type: 'too-deep'));
    }
    final typeVal = j['type'];
    final type = typeVal is String ? typeVal : '';
    return UiNode(
        id: id, component: UiComponent.parse(type, j, depth));
  }
}

/// Base for all components. Unknown `type` tags become [UiUnsupported]
/// carrying the raw payload for diagnostics (never rendered raw).
sealed class UiComponent {
  /// The wire tag (`markdown`, `form`, …).
  String get type;

  static UiComponent parse(String type, Map<String, dynamic> j,
      [int depth = 0]) {
    switch (type) {
      case 'markdown':
        return UiMarkdown.fromJson(j);
      case 'table':
        return UiTable.fromJson(j);
      case 'chart':
        return UiChart.fromJson(j);
      case 'metrics':
        return UiMetrics.fromJson(j);
      case 'list':
        return UiList.fromJson(j);
      case 'code':
        return UiCode.fromJson(j);
      case 'refs':
        return UiRefs.fromJson(j);
      case 'form':
        return UiForm.fromJson(j);
      case 'task_list':
        return UiTaskList.fromJson(j);
      case 'progress':
        return UiProgress.fromJson(j);
      case 'details':
        return UiDetails.fromJson(j, depth);
      case 'diff':
        return UiDiff.fromJson(j);
      case 'approval':
        return UiApproval.fromJson(j);
      case 'layout':
        return UiLayout.fromJson(j, depth);
      case 'custom':
        return UiCustom.fromJson(j, depth);
      default:
        return UiUnsupported(type: type.isEmpty ? 'unknown' : type);
    }
  }
}

String? _str(Map<String, dynamic> j, String k) {
  final v = j[k];
  return v is String ? v : null;
}

List<String> _strList(dynamic v) {
  if (v is! List) return const [];
  return v.whereType<String>().toList();
}

List<Map<String, dynamic>> _mapList(dynamic v) {
  if (v is! List) return const [];
  return v.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
}

/// `markdown {text, title?}`
class UiMarkdown extends UiComponent {
  @override
  String get type => 'markdown';
  final String text;
  final String? title;
  UiMarkdown({required this.text, this.title});
  factory UiMarkdown.fromJson(Map<String, dynamic> j) => UiMarkdown(
        text: _str(j, 'text') ?? '',
        title: _str(j, 'title'),
      );
}

/// `table {headers, rows, title?}` — `align` is display-only; ignored.
class UiTable extends UiComponent {
  @override
  String get type => 'table';
  final List<String> headers;
  final List<List<String>> rows;
  final String? title;
  UiTable({required this.headers, required this.rows, this.title});
  factory UiTable.fromJson(Map<String, dynamic> j) => UiTable(
        headers: _strList(j['headers']),
        rows: (j['rows'] as List? ?? const [])
            .map((r) => _strList(r))
            .toList(),
        title: _str(j, 'title'),
      );
}

/// `chart {chart_type, labels, series, title?}` — values may be long;
/// renderers should cap what they draw.
class UiChart extends UiComponent {
  @override
  String get type => 'chart';
  final String chartType; // line | bar | pie
  final List<String> labels;
  final List<UiSeries> series;
  final String? title;
  UiChart(
      {required this.chartType,
      required this.labels,
      required this.series,
      this.title});
  factory UiChart.fromJson(Map<String, dynamic> j) => UiChart(
        chartType: _str(j, 'chart_type') ?? 'bar',
        labels: _strList(j['labels']),
        series: _mapList(j['series']).map(UiSeries.fromJson).toList(),
        title: _str(j, 'title'),
      );
}

class UiSeries {
  final String name;
  final List<double> values;
  UiSeries({required this.name, required this.values});
  factory UiSeries.fromJson(Map<String, dynamic> j) => UiSeries(
        name: _str(j, 'name') ?? '',
        values: (j['values'] as List? ?? const [])
            .whereType<num>()
            .map((n) => n.toDouble())
            .toList(),
      );
}

/// `metrics {items: [{label, value, delta?}], title?}`
class UiMetrics extends UiComponent {
  @override
  String get type => 'metrics';
  final List<UiMetric> items;
  final String? title;
  UiMetrics({required this.items, this.title});
  factory UiMetrics.fromJson(Map<String, dynamic> j) => UiMetrics(
        items: _mapList(j['items']).map(UiMetric.fromJson).toList(),
        title: _str(j, 'title'),
      );
}

class UiMetric {
  final String label;
  final String value;
  final String? delta;
  UiMetric({required this.label, required this.value, this.delta});
  factory UiMetric.fromJson(Map<String, dynamic> j) => UiMetric(
        label: _str(j, 'label') ?? '',
        value: _str(j, 'value') ?? '',
        delta: _str(j, 'delta'),
      );
}

/// `list {items: [{text, status?}], title?}`
class UiList extends UiComponent {
  @override
  String get type => 'list';
  final List<UiListItem> items;
  final String? title;
  UiList({required this.items, this.title});
  factory UiList.fromJson(Map<String, dynamic> j) => UiList(
        items: _mapList(j['items']).map(UiListItem.fromJson).toList(),
        title: _str(j, 'title'),
      );
}

class UiListItem {
  final String text;
  final String? status;
  UiListItem({required this.text, this.status});
  factory UiListItem.fromJson(Map<String, dynamic> j) => UiListItem(
        text: _str(j, 'text') ?? '',
        status: _str(j, 'status'),
      );
}

/// `code {code, language?, title?}`
class UiCode extends UiComponent {
  @override
  String get type => 'code';
  final String code;
  final String? language;
  final String? title;
  UiCode({required this.code, this.language, this.title});
  factory UiCode.fromJson(Map<String, dynamic> j) => UiCode(
        code: _str(j, 'code') ?? '',
        language: _str(j, 'language'),
        title: _str(j, 'title'),
      );
}

/// `refs {items: [{title, url, note?}], title?}`
class UiRefs extends UiComponent {
  @override
  String get type => 'refs';
  final List<UiRef> items;
  final String? title;
  UiRefs({required this.items, this.title});
  factory UiRefs.fromJson(Map<String, dynamic> j) => UiRefs(
        items: _mapList(j['items']).map(UiRef.fromJson).toList(),
        title: _str(j, 'title'),
      );
}

class UiRef {
  final String title;
  final String url;
  final String? note;
  UiRef({required this.title, required this.url, this.note});
  factory UiRef.fromJson(Map<String, dynamic> j) => UiRef(
        title: _str(j, 'title') ?? '',
        url: _str(j, 'url') ?? '',
        note: _str(j, 'note'),
      );
}

/// A form field type.
enum UiFieldType { text, longText, number, boolean, secret, select }

/// `form {fields, submit, title?, description?}`
class UiForm extends UiComponent {
  @override
  String get type => 'form';
  final List<UiFormField> fields;
  final UiActionRef submit;
  final String? title;
  final String? description;
  UiForm(
      {required this.fields,
      required this.submit,
      this.title,
      this.description});
  factory UiForm.fromJson(Map<String, dynamic> j) => UiForm(
        fields:
            _mapList(j['fields']).map(UiFormField.fromJson).toList(),
        submit: UiActionRef.fromJson(
            (j['submit'] as Map?)?.cast<String, dynamic>() ?? {}),
        title: _str(j, 'title'),
        description: _str(j, 'description'),
      );
}

class UiFormField {
  final String name;
  final String label;
  final UiFieldType fieldType;
  final List<String> options; // select only
  final bool required;
  final String? defaultValue;
  final String? placeholder;
  UiFormField({
    required this.name,
    required this.label,
    required this.fieldType,
    this.options = const [],
    this.required = false,
    this.defaultValue,
    this.placeholder,
  });

  static UiFieldType _parseType(Map<String, dynamic> j) {
    final ft = (j['field_type'] as Map?)?.cast<String, dynamic>();
    final ftType = ft?['type'];
    switch (ftType is String ? ftType : null) {
      case 'long_text':
        return UiFieldType.longText;
      case 'number':
        return UiFieldType.number;
      case 'boolean':
        return UiFieldType.boolean;
      case 'secret':
        return UiFieldType.secret;
      case 'select':
        return UiFieldType.select;
      case 'text':
      default:
        return UiFieldType.text;
    }
  }

  factory UiFormField.fromJson(Map<String, dynamic> j) {
    final ft = (j['field_type'] as Map?)?.cast<String, dynamic>();
    return UiFormField(
      name: _str(j, 'name') ?? '',
      label: _str(j, 'label') ?? _str(j, 'name') ?? '',
      fieldType: _parseType(j),
      options: _strList(ft?['options']),
      required: j['required'] == true,
      defaultValue: _str(j, 'default'),
      placeholder: _str(j, 'placeholder'),
    );
  }
}

/// `task_list {items: [{id, label, state, detail?}], title?}`
class UiTaskList extends UiComponent {
  @override
  String get type => 'task_list';
  final List<UiTask> items;
  final String? title;
  UiTaskList({required this.items, this.title});
  factory UiTaskList.fromJson(Map<String, dynamic> j) => UiTaskList(
        items: _mapList(j['items']).map(UiTask.fromJson).toList(),
        title: _str(j, 'title'),
      );
}

class UiTask {
  final String id;
  final String label;
  final String state; // pending | running | done | failed | skipped
  final String? detail;
  UiTask(
      {required this.id,
      required this.label,
      required this.state,
      this.detail});
  factory UiTask.fromJson(Map<String, dynamic> j) => UiTask(
        id: _str(j, 'id') ?? '',
        label: _str(j, 'label') ?? '',
        state: _str(j, 'state') ?? 'pending',
        detail: _str(j, 'detail'),
      );
}

/// `progress {label, done, total}`
class UiProgress extends UiComponent {
  @override
  String get type => 'progress';
  final String label;
  final num done;
  final num total;
  UiProgress({required this.label, required this.done, required this.total});
  factory UiProgress.fromJson(Map<String, dynamic> j) {
    final d = j['done'];
    final t = j['total'];
    return UiProgress(
      label: _str(j, 'label') ?? '',
      done: d is num ? d : 0,
      total: t is num ? t : 0,
    );
  }
}

/// `details {summary, body}`
class UiDetails extends UiComponent {
  @override
  String get type => 'details';
  final String summary;
  final UiNode body;
  UiDetails({required this.summary, required this.body});
  factory UiDetails.fromJson(Map<String, dynamic> j, [int depth = 0]) =>
      UiDetails(
        summary: _str(j, 'summary') ?? '',
        body: UiNode._fromJson(
            (j['body'] as Map?)?.cast<String, dynamic>() ?? {}, depth + 1),
      );
}

/// `diff {files: [{path, hunks: [{header, lines: [{kind, text}]}]}], title?}`
class UiDiff extends UiComponent {
  @override
  String get type => 'diff';
  final List<UiDiffFile> files;
  final String? title;
  UiDiff({required this.files, this.title});
  factory UiDiff.fromJson(Map<String, dynamic> j) => UiDiff(
        files: _mapList(j['files']).map(UiDiffFile.fromJson).toList(),
        title: _str(j, 'title'),
      );
}

class UiDiffFile {
  final String path;
  final List<UiDiffHunk> hunks;
  UiDiffFile({required this.path, required this.hunks});
  factory UiDiffFile.fromJson(Map<String, dynamic> j) => UiDiffFile(
        path: _str(j, 'path') ?? '',
        hunks: _mapList(j['hunks']).map(UiDiffHunk.fromJson).toList(),
      );
}

class UiDiffHunk {
  final String header;
  final List<UiDiffLine> lines;
  UiDiffHunk({required this.header, required this.lines});
  factory UiDiffHunk.fromJson(Map<String, dynamic> j) => UiDiffHunk(
        header: _str(j, 'header') ?? '',
        lines: _mapList(j['lines']).map(UiDiffLine.fromJson).toList(),
      );
}

class UiDiffLine {
  final String kind; // context | add | del
  final String text;
  UiDiffLine({required this.kind, required this.text});
  factory UiDiffLine.fromJson(Map<String, dynamic> j) => UiDiffLine(
        kind: _str(j, 'kind') ?? 'context',
        text: _str(j, 'text') ?? '',
      );
}

/// `approval {title, detail, approve, deny, scope_hint?}`
class UiApproval extends UiComponent {
  @override
  String get type => 'approval';
  final String title;
  final String detail;
  final UiActionRef approve;
  final UiActionRef deny;
  final String? scopeHint;
  UiApproval({
    required this.title,
    required this.detail,
    required this.approve,
    required this.deny,
    this.scopeHint,
  });
  factory UiApproval.fromJson(Map<String, dynamic> j) => UiApproval(
        title: _str(j, 'title') ?? '',
        detail: _str(j, 'detail') ?? '',
        approve: UiActionRef.fromJson(
            (j['approve'] as Map?)?.cast<String, dynamic>() ?? {}),
        deny: UiActionRef.fromJson(
            (j['deny'] as Map?)?.cast<String, dynamic>() ?? {}),
        scopeHint: _str(j, 'scope_hint'),
      );
}

/// `layout {kind, children}`
class UiLayout extends UiComponent {
  @override
  String get type => 'layout';
  final String kind; // stack | columns | tabs
  final List<UiNode> children;
  UiLayout({required this.kind, required this.children});
  factory UiLayout.fromJson(Map<String, dynamic> j, [int depth = 0]) =>
      UiLayout(
        kind: _str(j, 'kind') ?? 'stack',
        children: _mapList(j['children'])
            .map((c) => UiNode._fromJson(c, depth + 1))
            .toList(),
      );
}

/// `custom {name, version, payload, fallback}` — always render `fallback`.
class UiCustom extends UiComponent {
  @override
  String get type => 'custom';
  final String name;
  final UiNode fallback;
  UiCustom({required this.name, required this.fallback});
  factory UiCustom.fromJson(Map<String, dynamic> j, [int depth = 0]) =>
      UiCustom(
        name: _str(j, 'name') ?? '',
        fallback: UiNode._fromJson(
            (j['fallback'] as Map?)?.cast<String, dynamic>() ?? {},
            depth + 1),
      );
}

/// Unknown or malformed component: safe, diagnosable, never rendered raw.
class UiUnsupported extends UiComponent {
  @override
  final String type;
  UiUnsupported({required this.type});
}

/// An action reference: `{action_id, label, kind}`.
class UiActionRef {
  final String actionId;
  final String label;
  final UiActionKind kind;
  UiActionRef(
      {required this.actionId, required this.label, required this.kind});
  factory UiActionRef.fromJson(Map<String, dynamic> j) => UiActionRef(
        actionId: _str(j, 'action_id') ?? '',
        label: _str(j, 'label') ?? '',
        kind: UiActionKind.parse(
            (j['kind'] as Map?)?.cast<String, dynamic>() ?? {}),
      );
}

/// Action kinds. Only the tag is needed client-side; the runtime
/// interprets the rest. `local` actions never reach the runtime.
enum UiActionKindTag { local, submit, tool, approval, unknown }

class UiActionKind {
  final UiActionKindTag tag;
  UiActionKind(this.tag);

  /// True when this action submits to the runtime.
  bool get isRemote => tag == UiActionKindTag.submit ||
      tag == UiActionKindTag.tool ||
      tag == UiActionKindTag.approval;

  static UiActionKind parse(Map<String, dynamic> j) {
    final kindVal = j['kind'];
    switch (kindVal is String ? kindVal : null) {
      case 'local':
        return UiActionKind(UiActionKindTag.local);
      case 'submit':
        return UiActionKind(UiActionKindTag.submit);
      case 'tool':
        return UiActionKind(UiActionKindTag.tool);
      case 'approval':
        return UiActionKind(UiActionKindTag.approval);
      default:
        return UiActionKind(UiActionKindTag.unknown);
    }
  }
}

/// The submission payload, mirroring `UiActionSubmission` exactly:
/// `ui_id` + `revision` (the displayed revision) + `node_id` +
/// `action_id` + `params` + `nonce`.
class UiActionSubmission {
  final String uiId;
  final int revision;
  final String nodeId;
  final String actionId;
  final Map<String, dynamic> params;
  final String nonce;

  UiActionSubmission({
    required this.uiId,
    required this.revision,
    required this.nodeId,
    required this.actionId,
    required this.params,
    required this.nonce,
  });

  Map<String, dynamic> toJson() => {
        'ui_id': uiId,
        'revision': revision,
        'node_id': nodeId,
        'action_id': actionId,
        'params': params,
        'nonce': nonce,
      };
}

/// The parsed outcome of a submission, from the dashboard envelope.
enum UiSubmitOutcome { executed, decided, denied, stale, error }

class UiSubmitResult {
  final UiSubmitOutcome outcome;
  final bool? approved; // decided only
  final String? result; // executed only
  final String? message; // error/denied/stale detail
  final int? status; // HTTP status

  UiSubmitResult._(this.outcome,
      {this.approved, this.result, this.message, this.status});

  factory UiSubmitResult.executed(String? result) =>
      UiSubmitResult._(UiSubmitOutcome.executed, result: result);
  factory UiSubmitResult.decided(bool approved) =>
      UiSubmitResult._(UiSubmitOutcome.decided, approved: approved);
  factory UiSubmitResult.denied(String? message, int? status) =>
      UiSubmitResult._(UiSubmitOutcome.denied,
          message: message, status: status);
  factory UiSubmitResult.stale(String? message) =>
      UiSubmitResult._(UiSubmitOutcome.stale, message: message);
  factory UiSubmitResult.error(String? message, int? status) =>
      UiSubmitResult._(UiSubmitOutcome.error,
          message: message, status: status);
}
