import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../theme.dart';
import 'buttons.dart';
import 'states.dart';

/// Shared admin-form helpers: text prompts and confirm sheets in the
/// Nyx visual language, so every management screen behaves the same.

/// Bottom-sheet text prompt. Returns the entered text, or null on cancel.
Future<String?> promptText(
  BuildContext context, {
  required String title,
  String? label,
  String? hint,
  String? initial,
  bool obscure = false,
  int maxLines = 1,
  TextInputType keyboardType = TextInputType.text,
  String confirmLabel = 'Save',
}) async {
  final ctrl = TextEditingController(text: initial ?? '');
  try {
    return await showPSheet<String>(
      context,
      SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              20, 8, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SheetHandle(),
              const SizedBox(height: 8),
              Text(title, style: PT.sectionTitle),
              const SizedBox(height: 16),
              TextField(
                controller: ctrl,
                autofocus: true,
                obscureText: obscure,
                maxLines: maxLines,
                keyboardType: keyboardType,
                style: PT.body,
                decoration: InputDecoration(
                  labelText: label,
                  hintText: hint,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TonalButton(
                        label: 'Cancel',
                        onTap: () => Navigator.pop(context)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GradientButton(
                      label: confirmLabel,
                      onTap: () =>
                          Navigator.pop(context, ctrl.text.trim()),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ).then((v) => (v == null || v.isEmpty) ? null : v);
  } finally {
    ctrl.dispose();
  }
}

/// Destructive-action confirm sheet. Returns true when confirmed.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String body,
  String confirmLabel = 'Confirm',
  bool destructive = false,
}) async {
  final ok = await showPSheet<bool>(
    context,
    SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SheetHandle(),
            const SizedBox(height: 8),
            Text(title, style: PT.sectionTitle),
            const SizedBox(height: 8),
            Text(body, style: PT.small),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TonalButton(
                      label: 'Cancel',
                      onTap: () => Navigator.pop(context, false)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DangerButton(
                    label: confirmLabel,
                    destructive: destructive,
                    onTap: () => Navigator.pop(context, true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  return ok == true;
}

/// Press feedback matching the Nyx button language (0.88 opacity while
/// pressed). Mirrors the private `_Pressable` in buttons.dart, which this
/// file cannot import.
class _Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  const _Pressable({required this.child, this.onTap});

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown:
          widget.onTap == null ? null : (_) => setState(() => _down = true),
      onTapUp:
          widget.onTap == null ? null : (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 120),
        opacity: _down ? 0.88 : 1.0,
        child: widget.child,
      ),
    );
  }
}

class _DangerButton extends StatelessWidget {
  final String label;
  final bool destructive;
  final VoidCallback onTap;

  const _DangerButton(
      {required this.label, required this.destructive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = destructive ? P.err : P.accent;
    return _Pressable(
      onTap: onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(P.r20),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        alignment: Alignment.center,
        child: Text(label,
            style: PT.label.copyWith(color: color, fontSize: 15)),
      ),
    );
  }
}

/// One-line result toast.
void toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// Error toast.
void toastError(BuildContext context, Object e) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Failed: $e')),
  );
}

/// Microphone-permission denial sheet: explains the block and offers a
/// one-tap path to the OS app settings. Use instead of a bare toast
/// wherever recording is gated on mic permission.
Future<void> micDeniedSheet(BuildContext context, {required String what}) async {
  await showPSheet(
    context,
    SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetHandle(),
            const SizedBox(height: 8),
            Text('Microphone is off', style: PT.sectionTitle),
            const SizedBox(height: 8),
            Text(
              'Pantheon needs microphone access $what. '
              'Enable it in Settings to continue.',
              style: PT.small,
            ),
            const SizedBox(height: 20),
            GradientButton(
              label: 'Open Settings',
              onTap: () async {
                Navigator.pop(context);
                await openAppSettings();
              },
            ),
            const SizedBox(height: 12),
            TonalButton(
              label: 'Not now',
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Label/value row for detail sheets.
class KvRow extends StatelessWidget {
  final String label;
  final String value;
  final bool mono;

  const KvRow(this.label, this.value, {super.key, this.mono = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: PT.meta),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: mono
                  ? PT.mono.copyWith(fontSize: 12, color: P.ink)
                  : PT.small.copyWith(color: P.ink),
            ),
          ),
        ],
      ),
    );
  }
}
