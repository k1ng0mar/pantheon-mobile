import 'package:flutter/material.dart';

import '../models/todo_item.dart';
import '../services/pantheon_api.dart';
import '../theme.dart';
import 'forms.dart';
import 'states.dart';

/// Reusable session-todos bottom sheet. Entry points: `/todos` and the
/// session header todos chip. Checkbox taps cycle
/// pending -> in_progress -> completed -> pending; every mutation saves
/// through `PUT /api/runs/:id/todos`.
Future<void> showTodosSheet(
    BuildContext context, PantheonApi api, String runId) {
  return showPSheet<void>(
    context,
    _TodosSheet(api: api, runId: runId),
  );
}

class _TodosSheet extends StatefulWidget {
  final PantheonApi api;
  final String runId;

  const _TodosSheet({required this.api, required this.runId});

  @override
  State<_TodosSheet> createState() => _TodosSheetState();
}

class _TodosSheetState extends State<_TodosSheet> {
  List<TodoItem>? _todos;
  String? _error;
  bool _saving = false;
  final _addCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _addCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final todos = await widget.api.getTodos(widget.runId);
      if (!mounted) return;
      setState(() {
        _todos = todos;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _persist(List<TodoItem> todos) async {
    setState(() {
      _todos = todos;
      _saving = true;
    });
    try {
      await widget.api.saveTodos(widget.runId, todos);
    } catch (e) {
      if (mounted) toastError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toggle(int i) {
    final todos = _todos!.toList();
    todos[i] = todos[i].copyWith(status: todos[i].nextStatus);
    _persist(todos);
  }

  void _remove(int i) {
    final todos = _todos!.toList()..removeAt(i);
    _persist(todos);
  }

  void _add() {
    final text = _addCtrl.text.trim();
    if (text.isEmpty || _todos == null) return;
    _addCtrl.clear();
    _persist([..._todos!, TodoItem(content: text)]);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            20, 8, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetHandle(),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Session todos', style: PT.sectionTitle),
                const Spacer(),
                if (_saving)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: P.accent),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!, style: PT.small.copyWith(color: P.err)),
              )
            else if (_todos == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: P.accent),
                  ),
                ),
              )
            else if (_todos!.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('No todos yet. Add the first one below.',
                    style: PT.small, textAlign: TextAlign.center),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _todos!.length,
                  itemBuilder: (_, i) => _row(_todos![i], i),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _addCtrl,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _add(),
                    style: PT.body,
                    decoration: const InputDecoration(
                      hintText: 'New todo…',
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _add,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                      gradient: P.gradient,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.add_rounded,
                        color: Colors.white, size: 22),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(TodoItem t, int i) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => _toggle(i),
            child: Container(
              width: 26,
              height: 26,
              margin: const EdgeInsets.only(top: 8, right: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: t.done
                      ? P.ok
                      : t.status == 'in_progress'
                          ? P.accent
                          : P.borderStrong,
                  width: 1.5,
                ),
                color: t.done
                    ? P.ok.withValues(alpha: 0.15)
                    : t.status == 'in_progress'
                        ? P.accentSoft
                        : Colors.transparent,
              ),
              alignment: Alignment.center,
              child: t.done
                  ? const Icon(Icons.check_rounded, size: 16, color: P.ok)
                  : t.status == 'in_progress'
                      ? const Icon(Icons.remove_rounded,
                          size: 16, color: P.accent)
                      : null,
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.content,
                    style: PT.rowTitle.copyWith(
                      fontSize: 14,
                      color: t.done ? P.inkFaint : P.ink,
                      decoration:
                          t.done ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  if (t.status == 'in_progress' &&
                      (t.activeForm?.isNotEmpty ?? false)) ...[
                    const SizedBox(height: 2),
                    Text(t.activeForm!, style: PT.meta),
                  ],
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded,
                size: 18, color: P.inkFaint),
            onPressed: () => _remove(i),
          ),
        ],
      ),
    );
  }
}
