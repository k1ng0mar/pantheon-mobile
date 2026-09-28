import 'package:flutter/material.dart';

/// Pantheon design tokens.
///
/// Nyx's discipline, re-inked: deep purple-navy surfaces, hairline borders
/// instead of shadows, one purple reserved for interactive/live elements.
/// Brand gradient: #7223FF → #4B00CD → #0C0046.
class P {
  // Brand
  static const accent = Color(0xFF8B5CFF); // interactive/live only
  static const accentDeep = Color(0xFF7223FF);
  static const accentDark = Color(0xFF4B00CD);
  static const accentInk = Color(0xFF0C0046);
  static const accentSoft = Color(0x248B5CFF); // 14% accent wash

  // Surfaces
  static const bg = Color(0xFF0B0130); // page
  static const surface = Color(0xFF12064A); // cards
  static const tonal = Color(0xFF1A0B5C); // filled tonal: fields, chips
  static const tabBar = Color(0xFF0A0128);

  // Hairlines (never shadows)
  static const border = Color(0x14FFFFFF); // ~8% white
  static const borderStrong = Color(0x29FFFFFF); // ~16% white
  static const divider = Color(0x0DFFFFFF); // ~5% white

  // Ink
  static const ink = Color(0xFFF4F1FF);
  static const inkSecondary = Color(0xFFC9BFF0);
  static const inkMuted = Color(0xFF9A8BD0);
  static const inkFaint = Color(0xFF6E5FA8);
  static const inkGhost = Color(0xFF4E4180);

  // Status
  static const ok = Color(0xFF4ADE80);
  static const warn = Color(0xFFFBBF24);
  static const err = Color(0xFFF87171);
  static const info = Color(0xFF7DD3FC);
  static const live = Color(0xFF8B5CFF);

  // Shape (Nyx radii)
  static const r4 = 4.0;
  static const r8 = 8.0;
  static const r12 = 12.0;
  static const r14 = 14.0;
  static const r16 = 16.0;
  static const r18 = 18.0;
  static const r20 = 20.0;
  static const r28 = 28.0;

  static const gradient = LinearGradient(
    colors: [Color(0xFF7223FF), Color(0xFF4B00CD), Color(0xFF0C0046)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const scrim = Color(0x9905001F);
}

/// Typography: Space Grotesk (display), Inter (body), JetBrains Mono (machine).
class PT {
  static const displayFamily = 'SpaceGrotesk';
  static const bodyFamily = 'Inter';
  static const monoFamily = 'JetBrainsMono';

  static const screenTitle = TextStyle(
    fontFamily: displayFamily,
    fontSize: 28,
    fontWeight: FontWeight.w600,
    color: P.ink,
    letterSpacing: -0.5,
    height: 1.15,
  );
  static const appBarTitle = TextStyle(
    fontFamily: displayFamily,
    fontSize: 22,
    fontWeight: FontWeight.w500,
    color: P.ink,
    letterSpacing: -0.25,
  );
  static const sectionTitle = TextStyle(
    fontFamily: displayFamily,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: P.ink,
    letterSpacing: -0.25,
  );
  static const cardTitle = TextStyle(
    fontFamily: displayFamily,
    fontSize: 17,
    fontWeight: FontWeight.w600,
    color: P.ink,
  );
  static const body = TextStyle(
    fontFamily: bodyFamily,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: P.ink,
    height: 1.45,
  );
  static const rowTitle = TextStyle(
    fontFamily: bodyFamily,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    color: P.ink,
    height: 1.4,
  );
  static const label = TextStyle(
    fontFamily: bodyFamily,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: P.ink,
  );
  static const small = TextStyle(
    fontFamily: bodyFamily,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: P.inkSecondary,
    height: 1.4,
  );
  static const meta = TextStyle(
    fontFamily: bodyFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: P.inkMuted,
  );
  static const faint = TextStyle(
    fontFamily: bodyFamily,
    fontSize: 11,
    fontWeight: FontWeight.w400,
    color: P.inkFaint,
  );

  /// The Nyx overline: 11sp uppercase, letterspaced group headers.
  static const overline = TextStyle(
    fontFamily: bodyFamily,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: P.inkMuted,
    letterSpacing: 1.5,
  );

  static const monoSm = TextStyle(
    fontFamily: monoFamily,
    fontSize: 11,
    fontWeight: FontWeight.w400,
    color: P.inkSecondary,
  );
  static const mono = TextStyle(
    fontFamily: monoFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: P.inkSecondary,
  );
  static const monoEyebrow = TextStyle(
    fontFamily: monoFamily,
    fontSize: 10,
    fontWeight: FontWeight.w500,
    color: P.inkFaint,
    letterSpacing: 0.8,
  );
}

ThemeData pantheonTheme() {
  final scheme = const ColorScheme.dark(
    primary: P.accent,
    secondary: P.accentDeep,
    surface: P.surface,
    error: P.err,
    onPrimary: Colors.white,
    onSurface: P.ink,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: P.bg,
    splashFactory: InkSparkle.splashFactory,
    dividerColor: P.divider,
    appBarTheme: const AppBarTheme(
      backgroundColor: P.bg,
      foregroundColor: P.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: PT.appBarTitle,
    ),
    cardTheme: CardThemeData(
      color: P.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(P.r16),
        side: const BorderSide(color: P.border, width: 1),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: P.tonal,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(P.r8),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(P.r8),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(P.r8),
        borderSide: const BorderSide(color: P.accent, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(P.r8),
        borderSide: const BorderSide(color: P.err, width: 2),
      ),
      labelStyle: PT.meta,
      hintStyle: const TextStyle(
        fontFamily: PT.bodyFamily,
        fontSize: 15,
        color: P.inkFaint,
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: P.surface,
      modalBackgroundColor: P.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(P.r28)),
      ),
      showDragHandle: true,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: const Color(0xFF1E1060),
      contentTextStyle: PT.small.copyWith(color: P.ink),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(P.r4)),
      behavior: SnackBarBehavior.floating,
    ),
    textTheme: const TextTheme(
      displayLarge: PT.screenTitle,
      titleLarge: PT.appBarTitle,
      titleMedium: PT.sectionTitle,
      bodyLarge: PT.body,
      bodyMedium: PT.small,
      labelLarge: PT.label,
    ),
  );
}

/// Compact number formatting: 1.2K, 3.4M.
String compactNum(num n) {
  if (n >= 1e9) return '${(n / 1e9).toStringAsFixed(1)}B';
  if (n >= 1e6) return '${(n / 1e6).toStringAsFixed(1)}M';
  if (n >= 1e3) return '${(n / 1e3).toStringAsFixed(1)}K';
  return n.toStringAsFixed(0);
}

String money(num usd) => '\$${usd.toDouble().toStringAsFixed(2)}';

String timeAgo(int tsMs, {bool future = false}) {
  final dt = DateTime.fromMillisecondsSinceEpoch(tsMs);
  final d =
      future ? dt.difference(DateTime.now()) : DateTime.now().difference(dt);
  String date() =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  if (future) {
    if (d.inMinutes < 1) return 'now';
    if (d.inMinutes < 60) return 'in ${d.inMinutes}m';
    if (d.inHours < 24) return 'in ${d.inHours}h';
    if (d.inDays < 30) return 'in ${d.inDays}d';
    return 'on ${date()}';
  }
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays < 30) return '${d.inDays}d ago';
  return date();
}
