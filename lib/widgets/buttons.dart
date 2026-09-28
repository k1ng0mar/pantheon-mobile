import 'package:flutter/material.dart';

import '../theme.dart';

/// Nyx buttons: 52dp tall, 20dp radius. Pressed = 0.88 opacity.
class _Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius borderRadius;

  const _Pressable({
    required this.child,
    this.onTap,
    this.borderRadius = const BorderRadius.all(Radius.circular(P.r20)),
  });

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

/// Primary CTA: brand gradient fill.
class GradientButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;

  const GradientButton({super.key, required this.label, this.onTap, this.icon});

  @override
  Widget build(BuildContext context) {
    return _Pressable(
      onTap: onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          gradient: onTap == null ? null : P.gradient,
          color: onTap == null ? P.tonal : null,
          borderRadius: BorderRadius.circular(P.r20),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              const Icon(Icons.arrow_forward_rounded,
                  size: 18, color: Colors.white),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: PT.label.copyWith(
                color: onTap == null ? P.inkFaint : Colors.white,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tonal button: soft accent wash fill.
class TonalButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const TonalButton({super.key, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return _Pressable(
      onTap: onTap,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: P.accentSoft,
          borderRadius: BorderRadius.circular(P.r20),
          border: Border.all(color: P.accent.withValues(alpha: 0.35)),
        ),
        alignment: Alignment.center,
        child: Text(label,
            style: PT.label.copyWith(color: P.accent, fontSize: 15)),
      ),
    );
  }
}

/// Small pill action (approval grant/deny style).
class PillButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Color color;
  final bool filled;

  const PillButton({
    super.key,
    required this.label,
    this.onTap,
    this.color = P.accent,
    this.filled = true,
  });

  @override
  Widget build(BuildContext context) {
    return _Pressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: filled ? color : Colors.transparent,
          border: Border.all(color: color, width: 1),
        ),
        child: Text(
          label,
          style: PT.label.copyWith(
            fontSize: 13,
            color: filled ? Colors.white : color,
          ),
        ),
      ),
    );
  }
}
