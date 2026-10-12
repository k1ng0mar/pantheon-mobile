import 'package:flutter/material.dart';

import '../theme.dart';

/// Floating chat composer: a single tonal pill holding the message field
/// and a compact toolbar (attach, model/mode, mic, send/stop).
///
/// This is presentation only — all behavior (send, stop, attachments,
/// voice notes, model picking) lives in the owning screen and arrives
/// here as callbacks. [above] renders staged attachments, chips and
/// similar rows between the transcript and the pill; [replacing] swaps
/// the field+toolbar for a transient state (voice-note recording,
/// transcription) while keeping the pill chrome.
///
/// The hint contract mirrors [sessionComposerDecoration]: the
/// placeholder stays on one line with an ellipsis so long agent names
/// never wrap, while typed text grows to [maxLines] lines.
class ChatComposer extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String agentName;

  /// False while a send is in flight (field disabled).
  final bool enabled;

  /// True when the field holds no text (send dims and is inert).
  final bool composerEmpty;

  /// True while the send request itself is in flight (spinner).
  final bool sending;

  /// True while a turn is running (send becomes stop).
  final bool live;

  final bool returnSends;
  final bool reduceMotion;

  /// Compact `Mode · provider · model` label; null hides the button.
  final String? modelModeLabel;

  final VoidCallback onSend;
  final VoidCallback onStop;
  final VoidCallback onStopLongPress;
  final VoidCallback onAttach;
  final VoidCallback onMic;
  final VoidCallback onModelTap;

  /// Rows rendered above the pill (attachments, chips, find bar…).
  final Widget? above;

  /// Replaces field+toolbar inside the pill (voice note, transcribing).
  final Widget? replacing;

  /// Spinner shown on the send button while the send request is in
  /// flight. The screen passes its preference-aware glyph here.
  final Widget? sendingGlyph;

  static const double _buttonSize = 44;

  const ChatComposer({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.agentName,
    required this.enabled,
    required this.composerEmpty,
    required this.sending,
    required this.live,
    required this.returnSends,
    required this.reduceMotion,
    required this.onSend,
    required this.onStop,
    required this.onStopLongPress,
    required this.onAttach,
    required this.onMic,
    required this.onModelTap,
    this.modelModeLabel,
    this.above,
    this.replacing,
    this.sendingGlyph,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (above != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: above!,
          ),
        ],
        Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 0),
          decoration: BoxDecoration(
            color: P.tonal,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: P.border),
          ),
          child: replacing ?? _fieldAndToolbar(context),
        ),
      ],
    );
  }

  Widget _fieldAndToolbar(BuildContext context) {
    final stopLive = !sending && live;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: controller,
          focusNode: focusNode,
          enabled: enabled,
          minLines: 1,
          maxLines: 5,
          textInputAction:
              returnSends ? TextInputAction.send : TextInputAction.newline,
          onSubmitted: returnSends ? (_) => onSend() : null,
          style: PT.body.copyWith(fontSize: 14),
          decoration: _pillDecoration(context),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
          child: Row(
            children: [
              _iconButton(
                icon: Icons.add_rounded,
                tooltip: 'Add to chat',
                onTap: onAttach,
              ),
              if (modelModeLabel != null) ...[
                const SizedBox(width: 2),
                Flexible(
                  child: _modelModeButton(context),
                ),
              ],
              const Spacer(),
              _iconButton(
                icon: Icons.mic_rounded,
                tooltip: 'Record voice note',
                onTap: onMic,
              ),
              const SizedBox(width: 2),
              _sendButton(stopLive),
            ],
          ),
        ),
      ],
    );
  }

  /// Borderless field decoration: the pill supplies the fill, so the
  /// field itself paints nothing. Hint keeps the single-line ellipsis
  /// contract.
  InputDecoration _pillDecoration(BuildContext context) {
    final themeHint = Theme.of(context).inputDecorationTheme.hintStyle;
    return InputDecoration(
      hintText: 'Message $agentName…',
      hintMaxLines: 1,
      hintStyle: (themeHint ?? const TextStyle())
          .copyWith(overflow: TextOverflow.ellipsis),
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
      filled: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    );
  }

  /// Compact `Plan · provider/model` button. The model picker and
  /// Plan/Build switch live behind it instead of as permanent rows.
  Widget _modelModeButton(BuildContext context) {
    return GestureDetector(
      onTap: onModelTap,
      child: Container(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.42),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          border: Border.all(color: P.border),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                modelModeLabel!,
                style: PT.small.copyWith(color: P.inkSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.expand_more_rounded, size: 14, color: P.inkMuted),
          ],
        ),
      ),
    );
  }

  Widget _iconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: _buttonSize,
          height: _buttonSize,
          child: Icon(icon,
              size: 22,
              color: P.inkSecondary,
              weight: 1.6,
              semanticLabel: tooltip),
        ),
      ),
    );
  }

  /// Send morphs into stop while a turn is in flight: tap stops at
  /// once, long-press opens the in-flight sheet (stop / steer / queue).
  /// Empty and idle, it dims instead of disappearing.
  Widget _sendButton(bool stopLive) {
    return GestureDetector(
      onTap: stopLive ? onStop : (composerEmpty ? null : onSend),
      onLongPress: stopLive ? onStopLongPress : null,
      child: AnimatedOpacity(
        duration: Duration(milliseconds: reduceMotion ? 0 : 150),
        opacity: sending ? 0.5 : (composerEmpty && !stopLive ? 0.35 : 1),
        child: Container(
          width: _buttonSize,
          height: _buttonSize,
          decoration: stopLive
              ? BoxDecoration(
                  color: P.err.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: P.err.withValues(alpha: 0.5), width: 1.5),
                )
              : const BoxDecoration(
                  gradient: P.gradient,
                  shape: BoxShape.circle,
                ),
          alignment: Alignment.center,
          child: sending
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: sendingGlyph ?? const _SendGlyph(),
                )
              : stopLive
                  ? Icon(Icons.stop_rounded,
                      color: P.err, size: 22, semanticLabel: 'Stop')
                  : Icon(Icons.arrow_upward_rounded,
                      color: Colors.white, size: 22, semanticLabel: 'Send'),
        ),
      ),
    );
  }
}

/// Tiny spinner glyph used while the send request is in flight.
class _SendGlyph extends StatelessWidget {
  const _SendGlyph();

  @override
  Widget build(BuildContext context) {
    return const CircularProgressIndicator(
      strokeWidth: 2,
      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
    );
  }
}
