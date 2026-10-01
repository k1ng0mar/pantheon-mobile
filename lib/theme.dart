import 'package:flutter/material.dart';

import 'services/app_preferences.dart';

/// Pantheon design tokens.
///
/// Nyx's discipline, re-inked: deep purple-navy surfaces, hairline borders
/// instead of shadows, one purple reserved for interactive/live elements.
/// Brand gradient: #7223FF → #4B00CD → #0C0046.
///
/// The palette is brightness-aware: [P.apply] selects the dark or light
/// [_Palette] (called once per frame by the app root before building), and
/// the dynamic colors are exposed as static getters so every existing
/// `P.surface` / `PT.small` reference follows the active theme without
/// being rewritten. Brand, status, radii and font families stay `static
/// const` — they are identical in both modes.
class _Palette {
  final Color bg;
  final Color surface;
  final Color tonal;
  final Color tabBar;
  final Color border;
  final Color borderStrong;
  final Color divider;
  final Color ink;
  final Color inkSecondary;
  final Color inkMuted;
  final Color inkFaint;

  const _Palette({
    required this.bg,
    required this.surface,
    required this.tonal,
    required this.tabBar,
    required this.border,
    required this.borderStrong,
    required this.divider,
    required this.ink,
    required this.inkSecondary,
    required this.inkMuted,
    required this.inkFaint,
  });
}

const _darkPalette = _Palette(
  bg: Color(0xFF0B0130),
  surface: Color(0xFF12064A),
  tonal: Color(0xFF1A0B5C),
  tabBar: Color(0xFF0A0128),
  border: Color(0x14FFFFFF),
  borderStrong: Color(0x29FFFFFF),
  divider: Color(0x0DFFFFFF),
  ink: Color(0xFFF4F1FF),
  inkSecondary: Color(0xFFC9BFF0),
  inkMuted: Color(0xFF9A8BD0),
  inkFaint: Color(0xFF6E5FA8),
);

const _lightPalette = _Palette(
  bg: Color(0xFFF5F3FC),
  surface: Color(0xFFFFFFFF),
  tonal: Color(0xFFEAE4FB),
  tabBar: Color(0xFFF5F3FC),
  border: Color(0x1A0C0046),
  borderStrong: Color(0x330C0046),
  divider: Color(0x140C0046),
  ink: Color(0xFF1B1140),
  inkSecondary: Color(0xFF3E3370),
  inkMuted: Color(0xFF5F5490),
  inkFaint: Color(0xFF8A7FB8),
);

class P {
  static _Palette _current = _darkPalette;

  /// Select the active palette. The app root calls this at the top of
  /// every build with the resolved brightness.
  static void apply(Brightness brightness) {
    _current = brightness == Brightness.light ? _lightPalette : _darkPalette;
  }

  // User custom-color overrides (null = palette default). Set by the app
  // root from AppPreferences every build.
  static Color? _accentOv;
  static Color? _bgOv;
  static Color? _surfaceOv;
  static Color? _tonalOv;

  static void setCustomColors({
    Color? accent,
    Color? bg,
    Color? surface,
    Color? tonal,
  }) {
    _accentOv = accent;
    _bgOv = bg;
    _surfaceOv = surface;
    _tonalOv = tonal;
  }

  // Brand (identical in both modes unless the user overrides the accent)
  static Color get accent => _accentOv ?? const Color(0xFF8B5CFF); // interactive/live only
  static Color get accentSoft => accent.withValues(alpha: 0.14); // 14% accent wash
  static const accentDeep = Color(0xFF7223FF);

  // Dynamic surfaces
  static Color get bg => _bgOv ?? _current.bg; // page
  static Color get surface => _surfaceOv ?? _current.surface; // cards
  static Color get tonal => _tonalOv ?? _current.tonal; // filled tonal: fields, chips
  static Color get tabBar => _current.tabBar;

  // Dynamic hairlines (never shadows)
  static Color get border => _current.border;
  static Color get borderStrong => _current.borderStrong;
  static Color get divider => _current.divider;

  // Dynamic ink
  static Color get ink => _current.ink;
  static Color get inkSecondary => _current.inkSecondary;
  static Color get inkMuted => _current.inkMuted;
  static Color get inkFaint => _current.inkFaint;

  // Status (identical in both modes)
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
///
/// Styles are getters (not const) because they reference the dynamic palette.
class PT {
  static const displayFamily = 'SpaceGrotesk';
  static const bodyFamily = 'Inter';
  static const monoFamily = 'JetBrainsMono';

  /// User-chosen body font (Appearance page). Display and mono stay fixed.
  static String get _bodyFont => AppPreferences.instance.bodyFont.value;

  static TextStyle get screenTitle => TextStyle(
        fontFamily: displayFamily,
        fontSize: 28,
        fontWeight: FontWeight.w600,
        color: P.ink,
        letterSpacing: -0.5,
        height: 1.15,
      );
  static TextStyle get appBarTitle => TextStyle(
        fontFamily: displayFamily,
        fontSize: 22,
        fontWeight: FontWeight.w500,
        color: P.ink,
        letterSpacing: -0.25,
      );
  static TextStyle get sectionTitle => TextStyle(
        fontFamily: displayFamily,
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: P.ink,
        letterSpacing: -0.25,
      );
  static TextStyle get cardTitle => TextStyle(
        fontFamily: displayFamily,
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: P.ink,
      );
  static TextStyle get body => TextStyle(
        fontFamily: _bodyFont,
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: P.ink,
        height: 1.45,
      );
  static TextStyle get rowTitle => TextStyle(
        fontFamily: _bodyFont,
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: P.ink,
        height: 1.4,
      );
  static TextStyle get label => TextStyle(
        fontFamily: _bodyFont,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: P.ink,
      );
  static TextStyle get small => TextStyle(
        fontFamily: _bodyFont,
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: P.inkSecondary,
        height: 1.4,
      );
  static TextStyle get meta => TextStyle(
        fontFamily: _bodyFont,
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: P.inkMuted,
      );
  static TextStyle get faint => TextStyle(
        fontFamily: _bodyFont,
        fontSize: 11,
        fontWeight: FontWeight.w400,
        color: P.inkFaint,
      );

  /// The Nyx overline: 11sp uppercase, letterspaced group headers.
  static TextStyle get overline => TextStyle(
        fontFamily: _bodyFont,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: P.inkMuted,
        letterSpacing: 1.5,
      );

  static TextStyle get monoSm => TextStyle(
        fontFamily: monoFamily,
        fontSize: 11,
        fontWeight: FontWeight.w400,
        color: P.inkSecondary,
      );
  static TextStyle get mono => TextStyle(
        fontFamily: monoFamily,
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: P.inkSecondary,
      );
  static TextStyle get monoEyebrow => TextStyle(
        fontFamily: monoFamily,
        fontSize: 10,
        fontWeight: FontWeight.w500,
        color: P.inkFaint,
        letterSpacing: 0.8,
      );
}

/// Build the Pantheon [ThemeData] for [brightness]. Applies the matching
/// palette first so every `P.*` reference captured below belongs to it
/// (colors are immutable, so this is safe to call for both modes in one
/// frame — the caller re-applies the live brightness afterwards).
ThemeData pantheonTheme(Brightness brightness, {bool compact = false}) {
  P.apply(brightness);
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: P.accent,
    onPrimary: Colors.white,
    secondary: P.accentDeep,
    onSecondary: Colors.white,
    surface: P.surface,
    onSurface: P.ink,
    error: P.err,
    onError: Colors.white,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: P.bg,
    splashFactory: InkSparkle.splashFactory,
    dividerColor: P.divider,
    visualDensity:
        compact ? VisualDensity.compact : VisualDensity.standard,
    appBarTheme: AppBarTheme(
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
        side: BorderSide(color: P.border, width: 1),
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
        borderSide: BorderSide(color: P.accent, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(P.r8),
        borderSide: BorderSide(color: P.err, width: 2),
      ),
      labelStyle: PT.meta,
      hintStyle: TextStyle(
        fontFamily: PT.bodyFamily,
        fontSize: 15,
        color: P.inkFaint,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: P.surface,
      modalBackgroundColor: P.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(P.r28)),
      ),
      // Sheets draw their own styled handle (SheetHandle); the framework
      // handle on top of it showed two pills on every sheet.
      showDragHandle: false,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor:
          dark ? const Color(0xFF1E1060) : const Color(0xFF241645),
      contentTextStyle: PT.small.copyWith(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(P.r4)),
      behavior: SnackBarBehavior.floating,
    ),
    textTheme: TextTheme(
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

String money(num usd) {
  final v = usd.toDouble();
  // Sub-cent but nonzero costs: show the floor as "<$0.01" rather than
  // a misleading "$0.00".
  if (v > 0 && v < 0.01) return '<\$0.01';
  return '\$${v.toStringAsFixed(2)}';
}

/// Absolute clock time: "10:29pm".
String clockTime(int tsMs) {
  final dt = DateTime.fromMillisecondsSinceEpoch(tsMs);
  var h = dt.hour % 12;
  if (h == 0) h = 12;
  final ap = dt.hour < 12 ? 'am' : 'pm';
  return '$h:${dt.minute.toString().padLeft(2, '0')}$ap';
}

/// Day divider label: Today / Yesterday / "Sep 28".
String dayLabel(DateTime day) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${months[day.month - 1]} ${day.day}';
}

String timeAgo(int tsMs, {bool future = false}) {
  final dt = DateTime.fromMillisecondsSinceEpoch(tsMs);
  final d =
      future ? dt.difference(DateTime.now()) : DateTime.now().difference(dt);
  String date() =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  if (future) {
    if (d.inMinutes < 1) return 'now';
    if (d.inMinutes < 60) return 'in ${d.inMinutes}m';
    if (d.inMinutes < 24 * 60) return 'in ${d.inHours}h';
    if (d.inDays < 30) return 'in ${d.inDays}d';
    return 'on ${date()}';
  }
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays < 30) return '${d.inDays}d ago';
  return date();
}
