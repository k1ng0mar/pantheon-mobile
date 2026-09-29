import 'package:flutter/material.dart';

import '../theme.dart';

/// The Nyx overline: 11sp uppercase, letterspaced group header.
class Overline extends StatelessWidget {
  final String text;

  const Overline(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? P.live;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Text(text.toUpperCase(), style: PT.overline),
    );
  }
}

/// Selectable pill chip: 1dp outline unselected, tonal fill + check selected.
class PillChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const PillChip({
    super.key,
    required this.label,
    required this.selected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: selected ? P.accentSoft : Colors.transparent,
          border: Border.all(
            color: selected ? P.accent : P.borderStrong,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
               Icon(Icons.check_rounded, size: 14, color: P.accent),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: PT.label.copyWith(
                fontSize: 13,
                color: selected ? P.ink : P.inkSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Read-only tonal status chip (green/red/neutral).
class StatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const StatusChip({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1),
      ),
      child: Text(
        label,
        style: PT.monoEyebrow.copyWith(color: color),
      ),
    );
  }
}

/// Pulsing live indicator (Nyx mic-dot pulse language).
class LiveDot extends StatefulWidget {
  final Color? color;
  final double size;

  const LiveDot({super.key, this.color, this.size = 8});

  @override
  State<LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.45 + 0.55 * _c.value),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.5 * _c.value),
              blurRadius: 8 * _c.value,
              spreadRadius: 2 * _c.value,
            ),
          ],
        ),
      ),
    );
  }
}
