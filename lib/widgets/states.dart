import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/app_preferences.dart';
import '../theme.dart';

/// Nyx empty state: centered thin icon, title, body, CTA.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final String? ctaLabel;
  final VoidCallback? onCta;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.ctaLabel,
    this.onCta,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: P.inkFaint, weight: 1.2),
            const SizedBox(height: 16),
            Text(title, style: PT.sectionTitle.copyWith(fontSize: 20)),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: Text(body, style: PT.small, textAlign: TextAlign.center),
            ),
            if (ctaLabel != null) ...[
              const SizedBox(height: 20),
              GestureDetector(
                onTap: onCta,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: P.gradient,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(ctaLabel!,
                      style: PT.label.copyWith(color: Colors.white)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shimmer skeleton block.
class Shimmer extends StatefulWidget {
  final double width;
  final double height;
  final double radius;

  const Shimmer(
      {super.key, required this.width, required this.height, this.radius = 8});

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat();
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
      builder: (_, __) => ShaderMask(
        shaderCallback: (bounds) => LinearGradient(
          colors:  [P.tonal, P.borderStrong, P.tonal],
          stops: [0.0, _c.value, 1.0],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ).createShader(bounds),
        child: Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: P.tonal,
            borderRadius: BorderRadius.circular(widget.radius),
          ),
        ),
      ),
    );
  }
}

/// Staggered list entrance: fade + rise, delayed per index.
class StaggerItem extends StatefulWidget {
  final int index;
  final Widget child;

  const StaggerItem({super.key, required this.index, required this.child});

  @override
  State<StaggerItem> createState() => _StaggerItemState();
}

class _StaggerItemState extends State<StaggerItem> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    final delay = Duration(milliseconds: (widget.index * 55).clamp(0, 440));
    Future.delayed(delay, () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppPreferences.instance.reduceMotion,
      builder: (_, reduceMotion, __) {
        // Reduce motion: no entrance animation, render the child directly.
        if (reduceMotion) return widget.child;
        return AnimatedOpacity(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOut,
          opacity: _visible ? 1 : 0,
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            offset: _visible ? Offset.zero : const Offset(0, 0.12),
            child: widget.child,
          ),
        );
      },
    );
  }
}

/// Animated count-up for KPI numbers.
class CountUp extends StatelessWidget {
  final num value;
  final String Function(num) format;
  final TextStyle style;

  const CountUp(
      {super.key,
      required this.value,
      required this.format,
      required this.style});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (_, v, __) => Text(format(v), style: style),
    );
  }
}

/// Nyx-style bottom sheet: 28dp top radius, drag handle, 90% max height.
Future<T?> showPSheet<T>(BuildContext context, Widget child) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: P.surface,
    barrierColor: P.scrim,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(P.r28)),
    ),
    builder: (ctx) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(ctx).height * 0.9,
      ),
      child: child,
    ),
  );
}

/// Drag handle pill for custom sheets.
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 32,
        height: 4,
        margin: const EdgeInsets.only(top: 12, bottom: 4),
        decoration: BoxDecoration(
          color: P.borderStrong,
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

/// Three-dot typing indicator (an alternative to the spinner).
class DotsLoading extends StatefulWidget {
  final Color? color;
  final double size;

  const DotsLoading({super.key, this.color, this.size = 6});

  @override
  State<DotsLoading> createState() => _DotsLoadingState();
}

class _DotsLoadingState extends State<DotsLoading>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? P.accent;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Builder(builder: (_) {
              final phase = (_c.value + i / 3) % 1.0;
              final opacity =
                  0.25 + 0.75 * (0.5 + 0.5 * math.sin(phase * 2 * math.pi));
              return Opacity(
                opacity: opacity,
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration:
                      BoxDecoration(shape: BoxShape.circle, color: color),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

/// Pulsing dot loading indicator (an alternative to the spinner).
class PulseLoading extends StatefulWidget {
  final Color? color;
  final double size;

  const PulseLoading({super.key, this.color, this.size = 12});

  @override
  State<PulseLoading> createState() => _PulseLoadingState();
}

class _PulseLoadingState extends State<PulseLoading>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? P.accent;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Opacity(
        opacity: 0.35 + 0.65 * _c.value,
        child: Transform.scale(
          scale: 0.7 + 0.3 * _c.value,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
        ),
      ),
    );
  }
}
