/// A session todo: {"content", "status", "active_form"?}.
/// Status cycles pending -> in_progress -> completed -> pending.
class TodoItem {
  final String content;
  final String status;
  final String? activeForm;

  TodoItem({required this.content, this.status = 'pending', this.activeForm});

  factory TodoItem.fromJson(Map<String, dynamic> j) => TodoItem(
        content: j['content'] as String? ?? '',
        status: j['status'] as String? ?? 'pending',
        activeForm: j['active_form'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'content': content,
        'status': status,
        if (activeForm != null) 'active_form': activeForm,
      };

  /// Sentinel so `copyWith` can explicitly clear `activeForm` to null.
  static const _sentinel = Object();

  TodoItem copyWith(
          {String? content, String? status, Object? activeForm = _sentinel}) =>
      TodoItem(
        content: content ?? this.content,
        status: status ?? this.status,
        activeForm:
            identical(activeForm, _sentinel) ? this.activeForm : activeForm as String?,
      );

  /// Next status in the checkbox cycle.
  String get nextStatus => switch (status) {
        'pending' => 'in_progress',
        'in_progress' => 'completed',
        _ => 'pending',
      };

  bool get done => status == 'completed';
}
