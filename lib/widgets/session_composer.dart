import 'package:flutter/material.dart';

/// Decoration for the session composer [TextField].
///
/// The placeholder ('Message <agent name>…') is forced onto a single
/// line with an ellipsis overflow so long agent names don't push it onto
/// a second row. The editable field itself is untouched: whatever
/// `minLines`/`maxLines` the [TextField] sets still governs typed text,
/// which keeps growing to multiple lines as the user types.
InputDecoration sessionComposerDecoration(BuildContext context,
    {required String agentName}) {
  final themeHint = Theme.of(context).inputDecorationTheme.hintStyle;
  return InputDecoration(
    hintText: 'Message $agentName…',
    // Single-line placeholder only; the editable text keeps its own
    // min/max lines on the TextField.
    hintMaxLines: 1,
    hintStyle: (themeHint ?? const TextStyle())
        .copyWith(overflow: TextOverflow.ellipsis),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  );
}
