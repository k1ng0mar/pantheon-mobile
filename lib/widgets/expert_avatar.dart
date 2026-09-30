import 'package:flutter/material.dart';

import '../theme.dart';

/// Parse a CSS hex color like "#7c5cff" (also accepts "7c5cff" or
/// 3-digit "#rgb"). Returns [P.accent] when the value is missing or
/// malformed, so member/expert cards always render.
Color hexColor(String? hex) {
  final h = (hex ?? '').trim().replaceFirst('#', '');
  final String full;
  if (h.length == 3) {
    full = h.split('').map((c) => '$c$c').join();
  } else if (h.length == 6) {
    full = h;
  } else {
    return P.accent;
  }
  final v = int.tryParse(full, radix: 16);
  if (v == null) return P.accent;
  return Color(0xFF000000 | v);
}

/// Initials for an avatar circle: first letters of the first two words,
/// uppercased ("Ava Stone" → "AS").
String initialsOf(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  final first = parts.first[0];
  final second = parts.length > 1 ? parts[1][0] : '';
  return '$first$second'.toUpperCase();
}

/// Colored avatar circle with initials (Nyx: tonal fill, colored ring).
/// Member/expert `icon` strings are not mapped to Material icons here —
/// their format is backend-defined, so initials are always reliable.
class MemberAvatar extends StatelessWidget {
  final String name;
  final String colorHex;
  final double size;

  const MemberAvatar({
    super.key,
    required this.name,
    required this.colorHex,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    final c = hexColor(colorHex);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: c.withValues(alpha: 0.20),
        border: Border.all(color: c.withValues(alpha: 0.65), width: 1.5),
      ),
      child: Text(
        initialsOf(name),
        style: PT.label.copyWith(
          color: c,
          fontSize: size * 0.38,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Overlapping member avatar stack for team cards: the first five
/// members, then a "+N" counter circle.
class AvatarStack extends StatelessWidget {
  final List<({String name, String colorHex})> members;
  final double size;

  const AvatarStack({super.key, required this.members, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final shown = members.take(5).toList();
    final extra = members.length - shown.length;
    final step = size * 0.62;
    return SizedBox(
      width: (shown.length + (extra > 0 ? 1 : 0) - 1) * step + size,
      height: size,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * step,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: P.surface, width: 2),
                ),
                child: MemberAvatar(
                  name: shown[i].name,
                  colorHex: shown[i].colorHex,
                  size: size,
                ),
              ),
            ),
          if (extra > 0)
            Positioned(
              left: shown.length * step,
              child: Container(
                width: size,
                height: size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: P.tonal,
                  border: Border.all(color: P.borderStrong, width: 1.5),
                ),
                child: Text(
                  '+$extra',
                  style: PT.label.copyWith(
                    color: P.inkSecondary,
                    fontSize: size * 0.32,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
