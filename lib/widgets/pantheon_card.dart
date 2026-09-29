import 'package:flutter/material.dart';

import '../theme.dart';

/// Hairline card: 16dp radius, 1dp border, zero shadow. The Nyx rule.
class PCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;

  const PCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.onTap,
    this.color,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? P.surface,
        borderRadius: BorderRadius.circular(P.r16),
        border: Border.all(color: borderColor ?? P.border, width: 1),
      ),
      child: child,
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(P.r16),
        splashColor: P.accentSoft,
        highlightColor: P.accentSoft,
        child: card,
      ),
    );
  }
}

/// 7dp status dot, top-aligned to the first text line (Nyx rule).
class StatusDot extends StatelessWidget {
  final Color color;
  final bool hollow;

  const StatusDot({super.key, required this.color, this.hollow = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: hollow ? Colors.transparent : color,
        border: hollow ? Border.all(color: color, width: 1.5) : null,
      ),
    );
  }
}

/// Nyx ListItem: 56dp min row, 15/500 title, 12 muted subtitle,
/// right-aligned mono supporting text, status dot, chevron.
class PRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? supporting;
  final Color? dotColor;
  final bool dotHollow;
  final VoidCallback? onTap;
  final Widget? trailing;

  const PRow({
    super.key,
    required this.title,
    this.subtitle,
    this.supporting,
    this.dotColor,
    this.dotHollow = false,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: P.accentSoft,
        highlightColor: P.accentSoft,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (dotColor != null) ...[
                StatusDot(color: dotColor!, hollow: dotHollow),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: PT.rowTitle),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: PT.meta),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (supporting != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(supporting!, style: PT.monoSm),
                ),
              trailing ??
                  (onTap != null
                      ?  Padding(
                          padding: EdgeInsets.only(top: 2, left: 8),
                          child: Icon(Icons.chevron_right_rounded,
                              size: 20, color: P.inkFaint),
                        )
                      : const SizedBox.shrink()),
            ],
          ),
        ),
      ),
    );
  }
}

/// A card containing a divided list of [PRow]s (internal #EFEAE0-style dividers).
class PRowCard extends StatelessWidget {
  final List<PRow> rows;

  const PRowCard({super.key, required this.rows});

  @override
  Widget build(BuildContext context) {
    return PCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            rows[i],
            if (i < rows.length - 1)
              const Divider(height: 1, thickness: 1, indent: 14, endIndent: 14),
          ],
        ],
      ),
    );
  }
}
