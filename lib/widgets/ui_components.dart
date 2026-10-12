import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../theme.dart';
import 'chat_markdown.dart';
import 'chips.dart';
import 'code_block.dart';

/// Native Flutter renderer for agent-native UI protocol documents.
///
/// Dispatches on the component type; unknown types degrade to
/// [UiUnsupportedView]. Interactive components (forms, approvals) report
/// submissions through [onAction] — the widget never executes actions
/// itself and performs no authorization; the runtime is the authority.
///
/// The [revision] must be the revision actually displayed; submissions
/// pin it so the runtime can reject stale documents.
class UiDocumentView extends StatelessWidget {
  final UiDocument document;
  final String uiId;
  final int revision;
  final UiActionHandler onAction;

  const UiDocumentView({
    super.key,
    required this.document,
    required this.uiId,
    required this.revision,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return UiNodeView(
      node: document.root,
      uiId: uiId,
      revision: revision,
      onAction: onAction,
    );
  }
}

/// Called when the user submits an interactive action. The returned
/// [UiSubmitResult] drives the submitting/success/error/stale states.
typedef UiActionHandler = Future<UiSubmitResult> Function(
    UiActionSubmission submission);

/// Renders one [UiNode], recursing for layout/details/custom-fallback.
class UiNodeView extends StatelessWidget {
  final UiNode node;
  final String uiId;
  final int revision;
  final UiActionHandler onAction;

  const UiNodeView({
    super.key,
    required this.node,
    required this.uiId,
    required this.revision,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final c = node.component;
    switch (c) {
      case UiMarkdown():
        return UiMarkdownView(markdown: c);
      case UiList():
        return UiListView(list: c);
      case UiForm():
        return UiFormView(
          nodeId: node.id,
          form: c,
          uiId: uiId,
          revision: revision,
          onAction: onAction,
        );
      case UiApproval():
        return UiApprovalView(
          nodeId: node.id,
          approval: c,
          uiId: uiId,
          revision: revision,
          onAction: onAction,
        );
      case UiTable():
        return UiTableView(table: c);
      case UiCode():
        return UiCodeView(code: c);
      case UiMetrics():
        return UiMetricsView(metrics: c);
      case UiTaskList():
        return UiTaskListView(taskList: c);
      case UiProgress():
        return UiProgressView(progress: c);
      case UiDetails():
        return UiDetailsView(
          details: c,
          uiId: uiId,
          revision: revision,
          onAction: onAction,
        );
      case UiDiff():
        return UiDiffView(diff: c);
      case UiLayout():
        return UiLayoutView(
          layout: c,
          uiId: uiId,
          revision: revision,
          onAction: onAction,
        );
      case UiRefs():
        return UiRefsView(refs: c);
      case UiChart():
        // Charts need a charting dependency; until one is justified,
        // show the values as a readable list (never silently drop).
        return UiChartFallbackView(chart: c);
      case UiCustom():
        return UiNodeView(
          node: c.fallback,
          uiId: uiId,
          revision: revision,
          onAction: onAction,
        );
      case UiUnsupported():
        return UiUnsupportedView(type: c.type);
    }
  }
}

Widget _title(String? title) {
  if (title == null || title.isEmpty) return const SizedBox.shrink();
  return Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(title, style: PT.label.copyWith(fontWeight: FontWeight.w700)),
  );
}

/// markdown — reuses the chat markdown renderer.
class UiMarkdownView extends StatelessWidget {
  final UiMarkdown markdown;
  const UiMarkdownView({super.key, required this.markdown});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(markdown.title),
        ChatMarkdown(text: markdown.text, textStyle: PT.body),
      ],
    );
  }
}

/// list — simple bulleted items with optional status.
class UiListView extends StatelessWidget {
  final UiList list;
  const UiListView({super.key, required this.list});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(list.title),
        for (final item in list.items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('•  ', style: PT.body.copyWith(color: P.inkFaint)),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      text: item.text,
                      style: PT.body,
                      children: item.status != null && item.status!.isNotEmpty
                          ? [
                              TextSpan(
                                text: '  [${item.status}]',
                                style: PT.small.copyWith(color: P.inkFaint),
                              ),
                            ]
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The per-action submission state machine.
enum _ActionState { idle, submitting, success, error }

/// Interactive form. Values are collected on submit; the runtime
/// validates against the form schema. Secret fields use obscured entry
/// and are never logged.
class UiFormView extends StatefulWidget {
  final String nodeId;
  final UiForm form;
  final String uiId;
  final int revision;
  final UiActionHandler onAction;

  const UiFormView({
    super.key,
    required this.nodeId,
    required this.form,
    required this.uiId,
    required this.revision,
    required this.onAction,
  });

  @override
  State<UiFormView> createState() => _UiFormViewState();
}

class _UiFormViewState extends State<UiFormView> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _textControllers;
  late final Map<String, bool> _bools;
  late final Map<String, String?> _selects;
  _ActionState _state = _ActionState.idle;
  String? _status;

  /// The nonce of the in-flight or last-failed submission. Retained
  /// across retries so a timeout retry reuses the same idempotency key
  /// — a fresh nonce after an uncertain timeout could double-execute.
  /// Cleared on success or revision change.
  String? _activeNonce;

  @override
  void initState() {
    super.initState();
    _textControllers = {};
    _bools = {};
    _selects = {};
    _initFields();
  }

  void _initFields() {
    for (final f in widget.form.fields) {
      switch (f.fieldType) {
        case UiFieldType.text ||
              UiFieldType.longText ||
              UiFieldType.number ||
              UiFieldType.secret:
          _textControllers[f.name] =
              TextEditingController(text: f.defaultValue ?? '');
        case UiFieldType.boolean:
          _bools[f.name] = f.defaultValue == 'true';
        case UiFieldType.select:
          _selects[f.name] =
              f.defaultValue ?? (f.options.isNotEmpty ? f.options.first : null);
      }
    }
  }

  @override
  void didUpdateWidget(UiFormView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The document moved under the user (new revision, or a different
    // document now at this transcript position). Drop the old input:
    // the server rejects submissions against superseded revisions, so
    // keeping stale values would only produce confusing rejections.
    // The fields are rebuilt from the newly displayed document.
    if (oldWidget.revision != widget.revision ||
        oldWidget.uiId != widget.uiId ||
        oldWidget.nodeId != widget.nodeId) {
      for (final c in _textControllers.values) {
        c.dispose();
      }
      _textControllers.clear();
      _bools.clear();
      _selects.clear();
      _initFields();
      _state = _ActionState.idle;
      _status = null;
      _activeNonce = null;
    }
  }

  @override
  void dispose() {
    for (final c in _textControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Collect validated params. Returns null and shows the field error
  /// when a required field is missing. Types mirror the protocol:
  /// numbers stay numeric, booleans stay boolean.
  Map<String, dynamic>? _collectParams() {
    if (!(_formKey.currentState?.validate() ?? false)) return null;
    final params = <String, dynamic>{};
    for (final f in widget.form.fields) {
      switch (f.fieldType) {
        case UiFieldType.text || UiFieldType.longText || UiFieldType.secret:
          final v = _textControllers[f.name]!.text;
          if (v.isNotEmpty) params[f.name] = v;
        case UiFieldType.number:
          final v = _textControllers[f.name]!.text;
          if (v.isNotEmpty) {
            final n = num.tryParse(v);
            if (n != null) params[f.name] = n;
          }
        case UiFieldType.boolean:
          params[f.name] = _bools[f.name] ?? false;
        case UiFieldType.select:
          final v = _selects[f.name];
          if (v != null) params[f.name] = v;
      }
    }
    return params;
  }

  Future<void> _submit() async {
    if (_state == _ActionState.submitting) return; // no double taps
    final params = _collectParams();
    if (params == null) return;
    final action = widget.form.submit;
    if (!action.kind.isRemote || action.actionId.isEmpty) {
      setState(() {
        _state = _ActionState.error;
        _status = 'This action is not submittable.';
      });
      return;
    }
    setState(() {
      _state = _ActionState.submitting;
      _status = null;
    });
    // The nonce is generated per logical submission and retained across
    // retries: a timeout retry must reuse the same idempotency key.
    final nonce = _activeNonce ??= _newNonce();
    final sub = UiActionSubmission(
      uiId: widget.uiId,
      revision: widget.revision,
      nodeId: widget.nodeId,
      actionId: action.actionId,
      params: params,
      nonce: nonce,
    );
    final result = await widget.onAction(sub);
    if (!mounted) return;
    setState(() {
      switch (result.outcome) {
        case UiSubmitOutcome.executed:
          _activeNonce = null; // succeeded; a new submission gets a new key
          _state = _ActionState.success;
          _status =
              'Done${result.result != null && result.result!.isNotEmpty ? ': ${_truncate(result.result!, 200)}' : ''}';
        case UiSubmitOutcome.decided:
          _activeNonce = null;
          _state = _ActionState.success;
          _status = (result.approved ?? false) ? 'Approved' : 'Denied';
        case UiSubmitOutcome.denied:
          _state = _ActionState.error;
          _status = result.message ?? 'Action denied.';
        case UiSubmitOutcome.stale:
          _activeNonce = null; // superseded; the refresh brings a new doc
          _state = _ActionState.error;
          _status = 'This form was updated — refreshing.';
        case UiSubmitOutcome.error:
          // Keep _activeNonce: the outcome is uncertain, so a retry must
          // reuse the same key for the server's replay protection.
          _state = _ActionState.error;
          _status = result.message ?? 'Submission failed.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final submitting = _state == _ActionState.submitting;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: P.surface,
        borderRadius: BorderRadius.circular(P.r16),
        border: Border.all(color: P.border),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _title(widget.form.title),
            if (widget.form.description != null &&
                widget.form.description!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(widget.form.description!,
                    style: PT.small.copyWith(color: P.inkFaint)),
              ),
            for (final f in widget.form.fields) _field(f, submitting),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: submitting ? null : _submit,
                child: submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(widget.form.submit.label.isEmpty
                        ? 'Submit'
                        : widget.form.submit.label),
              ),
            ),
            if (_status != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _status!,
                  style: PT.small.copyWith(
                    color: _state == _ActionState.error ? P.err : P.ok,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _field(UiFormField f, bool submitting) {
    final label = '${f.label}${f.required ? ' *' : ''}';
    String? required(String? v) =>
        f.required && (v == null || v.isEmpty) ? 'Required' : null;

    switch (f.fieldType) {
      case UiFieldType.longText:
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextFormField(
            controller: _textControllers[f.name],
            enabled: !submitting,
            minLines: 3,
            maxLines: 6,
            decoration:
                InputDecoration(labelText: label, hintText: f.placeholder),
            validator: required,
          ),
        );
      case UiFieldType.number:
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextFormField(
            controller: _textControllers[f.name],
            enabled: !submitting,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration:
                InputDecoration(labelText: label, hintText: f.placeholder),
            validator: (v) {
              final r = required(v);
              if (r != null) return r;
              if (v != null && v.isNotEmpty && num.tryParse(v) == null) {
                return 'Enter a number';
              }
              return null;
            },
          ),
        );
      case UiFieldType.secret:
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextFormField(
            controller: _textControllers[f.name],
            enabled: !submitting,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            decoration:
                InputDecoration(labelText: label, hintText: f.placeholder),
            validator: required,
          ),
        );
      case UiFieldType.boolean:
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: InkWell(
            onTap: submitting
                ? null
                : () =>
                    setState(() => _bools[f.name] = !(_bools[f.name] ?? false)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Checkbox(
                    value: _bools[f.name] ?? false,
                    onChanged: submitting
                        ? null
                        : (v) => setState(() => _bools[f.name] = v ?? false),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(label, style: PT.body)),
                ],
              ),
            ),
          ),
        );
      case UiFieldType.select:
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: DropdownButtonFormField<String>(
            initialValue: _selects[f.name],
            decoration: InputDecoration(labelText: label),
            items: [
              for (final o in f.options)
                DropdownMenuItem(value: o, child: Text(o)),
            ],
            onChanged:
                submitting ? null : (v) => setState(() => _selects[f.name] = v),
            validator: required,
          ),
        );
      case UiFieldType.text:
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextFormField(
            controller: _textControllers[f.name],
            enabled: !submitting,
            decoration:
                InputDecoration(labelText: label, hintText: f.placeholder),
            validator: required,
          ),
        );
    }
  }
}

/// Approval card with approve/deny. Decisions go through the UI
/// protocol action path — never the legacy approvals queue.
class UiApprovalView extends StatefulWidget {
  final String nodeId;
  final UiApproval approval;
  final String uiId;
  final int revision;
  final UiActionHandler onAction;

  const UiApprovalView({
    super.key,
    required this.nodeId,
    required this.approval,
    required this.uiId,
    required this.revision,
    required this.onAction,
  });

  @override
  State<UiApprovalView> createState() => _UiApprovalViewState();
}

class _UiApprovalViewState extends State<UiApprovalView> {
  _ActionState _state = _ActionState.idle;
  String? _status;

  /// Retained across retries (see _UiFormViewState._activeNonce).
  String? _activeNonce;

  @override
  void didUpdateWidget(UiApprovalView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new revision means a new decision is required; the old
    // approved/denied state belongs to the superseded document.
    if (oldWidget.revision != widget.revision ||
        oldWidget.uiId != widget.uiId ||
        oldWidget.nodeId != widget.nodeId) {
      _state = _ActionState.idle;
      _status = null;
      _activeNonce = null;
    }
  }

  Future<void> _decide(UiActionRef action) async {
    if (_state == _ActionState.submitting || _state == _ActionState.success) {
      return; // decided cards stay decided
    }
    if (!action.kind.isRemote || action.actionId.isEmpty) return;
    setState(() {
      _state = _ActionState.submitting;
      _status = null;
    });
    final nonce = _activeNonce ??= _newNonce();
    final sub = UiActionSubmission(
      uiId: widget.uiId,
      revision: widget.revision,
      nodeId: widget.nodeId,
      actionId: action.actionId,
      params: const {},
      nonce: nonce,
    );
    final result = await widget.onAction(sub);
    if (!mounted) return;
    setState(() {
      switch (result.outcome) {
        case UiSubmitOutcome.decided:
          _activeNonce = null;
          _state = _ActionState.success;
          _status =
              (result.approved ?? false) ? 'Approved — resuming' : 'Denied';
        case UiSubmitOutcome.stale:
          _activeNonce = null;
          _state = _ActionState.error;
          _status = 'Already decided — refreshing.';
        case UiSubmitOutcome.denied:
        case UiSubmitOutcome.error:
          // Keep _activeNonce for safe retry (see _UiFormViewState).
          _state = _ActionState.error;
          _status = result.message ?? 'Decision failed.';
        case UiSubmitOutcome.executed:
          _activeNonce = null;
          _state = _ActionState.error;
          _status = 'Unexpected result.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final busy = _state == _ActionState.submitting;
    final done = _state == _ActionState.success;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: P.surface,
        borderRadius: BorderRadius.circular(P.r16),
        border: Border.all(color: P.warn.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, size: 18, color: P.warn),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.approval.title.isEmpty
                      ? 'Approval needed'
                      : widget.approval.title,
                  style: PT.label
                      .copyWith(fontWeight: FontWeight.w700, color: P.warn),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ChatMarkdown(text: widget.approval.detail, textStyle: PT.body),
          if (widget.approval.scopeHint != null &&
              widget.approval.scopeHint!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('scope: ${widget.approval.scopeHint}',
                  style: PT.small.copyWith(color: P.inkFaint)),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: busy || done
                      ? null
                      : () => _decide(widget.approval.approve),
                  child: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(widget.approval.approve.label.isEmpty
                          ? 'Approve'
                          : widget.approval.approve.label),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      busy || done ? null : () => _decide(widget.approval.deny),
                  child: Text(widget.approval.deny.label.isEmpty
                      ? 'Deny'
                      : widget.approval.deny.label),
                ),
              ),
            ],
          ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _status!,
                style: PT.small.copyWith(
                  color: _state == _ActionState.error ? P.err : P.ok,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// table — horizontal scroll on narrow screens.
class UiTableView extends StatelessWidget {
  final UiTable table;
  const UiTableView({super.key, required this.table});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(table.title),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingTextStyle: PT.small.copyWith(fontWeight: FontWeight.w700),
            dataTextStyle: PT.small,
            columns: [
              for (final h in table.headers) DataColumn(label: Text(h)),
            ],
            rows: [
              for (final r in table.rows)
                DataRow(
                  cells: [
                    for (var i = 0; i < table.headers.length; i++)
                      DataCell(Text(i < r.length ? r[i] : '')),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// code — reuses the chat code block (with copy button).
class UiCodeView extends StatelessWidget {
  final UiCode code;
  const UiCodeView({super.key, required this.code});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(code.title ?? code.language),
        CodeBlock(code: code.code, languageTag: code.language ?? ''),
      ],
    );
  }
}

/// metrics — compact stat cards.
class UiMetricsView extends StatelessWidget {
  final UiMetrics metrics;
  const UiMetricsView({super.key, required this.metrics});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(metrics.title),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in metrics.items)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: P.surface,
                  borderRadius: BorderRadius.circular(P.r12),
                  border: Border.all(color: P.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.value,
                        style: PT.label.copyWith(fontWeight: FontWeight.w700)),
                    Text(m.label, style: PT.small),
                    if (m.delta != null)
                      Text(m.delta!,
                          style: PT.small.copyWith(color: P.inkFaint)),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// task_list — checkbox-style rows.
class UiTaskListView extends StatelessWidget {
  final UiTaskList taskList;
  const UiTaskListView({super.key, required this.taskList});

  @override
  Widget build(BuildContext context) {
    IconData iconFor(String state) {
      switch (state) {
        case 'done':
          return Icons.check_box_rounded;
        case 'failed':
          return Icons.disabled_by_default_rounded;
        case 'running':
          return Icons.play_circle_outline_rounded;
        case 'skipped':
          return Icons.skip_next_rounded;
        default:
          return Icons.check_box_outline_blank_rounded;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(taskList.title),
        for (final t in taskList.items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(iconFor(t.state), size: 18, color: P.inkFaint),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.label, style: PT.body),
                      if (t.detail != null && t.detail!.isNotEmpty)
                        Text(t.detail!,
                            style: PT.small.copyWith(color: P.inkFaint)),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// progress — linear indicator with label.
class UiProgressView extends StatelessWidget {
  final UiProgress progress;
  const UiProgressView({super.key, required this.progress});

  @override
  Widget build(BuildContext context) {
    final total = progress.total.toDouble();
    final done = progress.done.toDouble().clamp(0, total);
    final pct = total > 0 ? done / total : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: Text(progress.label, style: PT.label)),
            Text('${(pct * 100).round()}%',
                style: PT.small.copyWith(color: P.inkFaint)),
          ],
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(value: pct),
      ],
    );
  }
}

/// details — expandable section.
class UiDetailsView extends StatelessWidget {
  final UiDetails details;
  final String uiId;
  final int revision;
  final UiActionHandler onAction;
  const UiDetailsView({
    super.key,
    required this.details,
    required this.uiId,
    required this.revision,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: P.border),
        borderRadius: BorderRadius.circular(P.r12),
      ),
      child: ExpansionTile(
        title: Text(details.summary.isEmpty ? 'Details' : details.summary,
            style: PT.label),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: UiNodeView(
              node: details.body,
              uiId: uiId,
              revision: revision,
              onAction: onAction,
            ),
          ),
        ],
      ),
    );
  }
}

/// diff — file hunks with add/del coloring.
class UiDiffView extends StatelessWidget {
  final UiDiff diff;
  const UiDiffView({super.key, required this.diff});

  @override
  Widget build(BuildContext context) {
    Color bgFor(String kind) {
      switch (kind) {
        case 'add':
          return P.ok.withValues(alpha: 0.12);
        case 'del':
          return P.err.withValues(alpha: 0.12);
        default:
          return Colors.transparent;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(diff.title),
        for (final f in diff.files) ...[
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 2),
            child: Text(f.path, style: PT.monoSm),
          ),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: P.surface,
              borderRadius: BorderRadius.circular(P.r12),
              border: Border.all(color: P.border),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final h in f.hunks) ...[
                    if (h.header.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 6, 10, 2),
                        child: Text(h.header,
                            style: PT.monoSm.copyWith(color: P.inkFaint)),
                      ),
                    for (final l in h.lines)
                      Container(
                        width: double.infinity,
                        color: bgFor(l.kind),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 1),
                        child: Text(
                          '${l.kind == 'add' ? '+' : l.kind == 'del' ? '-' : ' '}${l.text}',
                          style: PT.monoSm,
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// layout — stack/columns/tabs. Columns fall back to stacked on narrow
/// screens (the protocol explicitly allows this).
class UiLayoutView extends StatelessWidget {
  final UiLayout layout;
  final String uiId;
  final int revision;
  final UiActionHandler onAction;
  const UiLayoutView({
    super.key,
    required this.layout,
    required this.uiId,
    required this.revision,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    Widget child(UiNode n) => UiNodeView(
          node: n,
          uiId: uiId,
          revision: revision,
          onAction: onAction,
        );

    switch (layout.kind) {
      case 'tabs':
        // Segmented tabs + IndexedStack: the content decides the height,
        // so tabbed layouts never clip or waste space in the chat feed.
        // IndexedStack keeps inactive tabs alive (form input survives
        // a tab switch). An empty tab list renders nothing instead of
        // crashing the old TabController(length: 0).
        if (layout.children.isEmpty) return const SizedBox.shrink();
        return _UiTabs(
          labels: [
            for (final indexed in layout.children.indexed)
              'Tab ${indexed.$1 + 1}'
          ],
          children: [for (final n in layout.children) child(n)],
        );
      case 'columns':
        return LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 480) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [for (final n in layout.children) child(n)],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final n in layout.children) Expanded(child: child(n)),
              ],
            );
          },
        );
      case 'stack':
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (final n in layout.children) child(n)],
        );
    }
  }
}

/// refs — link list.
class UiRefsView extends StatelessWidget {
  final UiRefs refs;
  const UiRefsView({super.key, required this.refs});

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(refs.title),
        for (final r in refs.items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => _openUrl(r.url),
                  child: Text(r.title.isEmpty ? r.url : r.title,
                      style: PT.body.copyWith(
                          color: P.accent,
                          decoration: TextDecoration.underline)),
                ),
                if (r.note != null && r.note!.isNotEmpty)
                  Text(r.note!, style: PT.small.copyWith(color: P.inkFaint)),
              ],
            ),
          ),
      ],
    );
  }
}

/// Tabbed layout with content-driven height: a segmented control picks
/// the visible child; [IndexedStack] keeps every tab's state alive so
/// form input and scroll positions survive tab switches.
class _UiTabs extends StatefulWidget {
  final List<String> labels;
  final List<Widget> children;
  const _UiTabs({required this.labels, required this.children});

  @override
  State<_UiTabs> createState() => _UiTabsState();
}

class _UiTabsState extends State<_UiTabs> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final labels = widget.labels;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final indexed in labels.indexed)
                Padding(
                  padding: EdgeInsets.only(
                      right: indexed.$1 == labels.length - 1 ? 0 : 8),
                  child: SegTab(
                    label: indexed.$2,
                    selected: indexed.$1 == _index,
                    onTap: () => setState(() => _index = indexed.$1),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        IndexedStack(index: _index, children: widget.children),
      ],
    );
  }
}

/// chart placeholder — values as a readable list until a charting
/// dependency is justified.
class UiChartFallbackView extends StatelessWidget {
  final UiChart chart;
  const UiChartFallbackView({super.key, required this.chart});

  @override
  Widget build(BuildContext context) {
    final series = chart.series.isNotEmpty ? chart.series.first : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(chart.title ?? '${chart.chartType} chart'),
        if (series != null)
          for (var i = 0; i < chart.labels.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: Text(chart.labels[i], style: PT.small)),
                  Text(
                    i < series.values.length ? _fmtNum(series.values[i]) : '—',
                    style: PT.monoSm,
                  ),
                ],
              ),
            )
        else
          Text('No data', style: PT.small.copyWith(color: P.inkFaint)),
      ],
    );
  }

  String _fmtNum(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
}

/// Safe fallback for unknown component types.
class UiUnsupportedView extends StatelessWidget {
  final String type;
  const UiUnsupportedView({super.key, required this.type});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: P.border),
        borderRadius: BorderRadius.circular(P.r12),
      ),
      child: Text(
        'Unsupported content ($type) — update the app to view it.',
        style:
            PT.small.copyWith(color: P.inkFaint, fontStyle: FontStyle.italic),
      ),
    );
  }
}

String _truncate(String s, int max) =>
    s.length <= max ? s : '${s.substring(0, max)}…';

/// Per-tap unique nonce (UUID v4). Uniqueness — not secrecy — is the
/// requirement: the server treats the nonce as an opaque idempotency
/// key for replay protection.
String _newNonce() => const Uuid().v4();
