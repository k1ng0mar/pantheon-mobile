/// A parked `ask_user` question: `pending_input` on the run detail.
/// {call_id, question, options}.
class PendingInput {
  final String callId;
  final String question;
  final List<String> options;

  PendingInput({
    required this.callId,
    required this.question,
    this.options = const [],
  });

  factory PendingInput.fromJson(Map<String, dynamic> j) => PendingInput(
        callId: j['call_id'] as String? ?? '',
        question: j['question'] as String? ?? '',
        options: (j['options'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
      );
}
