import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-level preferences: appearance + notifications.
///
/// Persisted in SharedPreferences (nothing sensitive here — the auth token
/// stays in [SettingsStore]'s secure storage). Appearance notifiers are
/// merged into [appearance] so the app root rebuilds the moment a page
/// changes a value; every setter persists before returning.
class AppPreferences {
  AppPreferences._();
  static final AppPreferences instance = AppPreferences._();

  static const _kThemeMode = 'app.theme_mode'; // system|light|dark
  static const _kTextScale = 'app.text_scale';
  static const _kCompact = 'app.compact_density';

  static const _kCustomAccent = 'app.color.accent';
  static const _kCustomBg = 'app.color.bg';
  static const _kCustomSurface = 'app.color.surface';
  static const _kCustomTonal = 'app.color.tonal';

  static const _kBodyFont = 'app.body_font'; // Inter|SpaceGrotesk|JetBrainsMono
  static const _kBubbleStyle = 'app.bubble'; // default|bubbles
  static const _kChatDensity = 'app.chat_density'; // comfortable|compact
  static const _kChatBg = 'app.chat_bg'; // default|tinted|dim
  static const _kLoadingStyle = 'app.loading'; // spinner|dots|pulse
  static const _kReturnSends = 'app.return_sends';

  static const _kShowTs = 'app.show_timestamps';
  static const _kTsFormat = 'app.ts_format'; // relative|absolute
  static const _kDateDividers = 'app.date_dividers';

  static const _kReduceMotion = 'app.reduce_motion';
  static const _kHaptics = 'app.haptics';

  static const _kCodeTheme = 'app.code_theme'; // github|dracula|atom-one-dark
  static const _kAgentAvatar = 'app.agent_avatar_path';

  static const _kNotifMaster = 'notif.enabled';
  static const _kNotifRunCompleted = 'notif.run_completed';
  static const _kNotifRunFailed = 'notif.run_failed';
  static const _kNotifApprovalParked = 'notif.approval_parked';
  static const _kNotifSchedule = 'notif.schedule_results';
  static const _kNotifNightly = 'notif.nightly_repair';
  static const _kQuietOn = 'notif.quiet_enabled';
  static const _kQuietStart = 'notif.quiet_start'; // minutes since midnight
  static const _kQuietEnd = 'notif.quiet_end';
  static const _kMutedSessions = 'notif.muted_sessions';
  static const _kNotifSound = 'notif.sound';

  final themeMode = ValueNotifier<ThemeMode>(ThemeMode.system);
  final textScale = ValueNotifier<double>(1.0);
  final compactDensity = ValueNotifier<bool>(false);

  final customAccent = ValueNotifier<Color?>(null);
  final customBg = ValueNotifier<Color?>(null);
  final customSurface = ValueNotifier<Color?>(null);
  final customTonal = ValueNotifier<Color?>(null);

  final bodyFont = ValueNotifier<String>('Inter');
  final bubbleStyle = ValueNotifier<String>('default');
  final chatDensity = ValueNotifier<String>('comfortable');
  final chatBg = ValueNotifier<String>('default');
  final loadingStyle = ValueNotifier<String>('spinner');
  final returnSends = ValueNotifier<bool>(true);

  final showTimestamps = ValueNotifier<bool>(false);
  final timestampFormat = ValueNotifier<String>('relative');
  final dateDividers = ValueNotifier<bool>(false);

  final reduceMotion = ValueNotifier<bool>(false);
  final hapticsEnabled = ValueNotifier<bool>(true);

  /// Code block theme id: 'github', 'dracula', or 'atom-one-dark'.
  final codeTheme = ValueNotifier<String>('dracula');

  /// Custom agent avatar image path (device gallery pick), or null for
  /// the default avatar.
  final agentAvatarPath = ValueNotifier<String?>(null);

  final notificationsEnabled = ValueNotifier<bool>(true);
  final notifRunCompleted = ValueNotifier<bool>(true);
  final notifRunFailed = ValueNotifier<bool>(true);
  final notifApprovalParked = ValueNotifier<bool>(true);
  final notifScheduleResults = ValueNotifier<bool>(true);
  final notifNightlyRepair = ValueNotifier<bool>(true);
  final quietHoursEnabled = ValueNotifier<bool>(false);
  final quietStartMin = ValueNotifier<int>(1320); // 22:00
  final quietEndMin = ValueNotifier<int>(420); // 07:00
  final mutedSessions = ValueNotifier<Set<String>>({});
  final notifSoundEnabled = ValueNotifier<bool>(true);

  /// Bumped by every appearance setter so the app root rebuilds once.
  final _appearanceTick = ValueNotifier<int>(0);
  late final Listenable appearance = Listenable.merge(
      [themeMode, textScale, compactDensity, _appearanceTick]);

  bool _ready = false;

  void _bump() => _appearanceTick.value++;

  Future<void> init() async {
    if (_ready) return;
    final p = await SharedPreferences.getInstance();
    themeMode.value = _modeFrom(p.getString(_kThemeMode));
    textScale.value = p.getDouble(_kTextScale) ?? 1.0;
    compactDensity.value = p.getBool(_kCompact) ?? false;

    customAccent.value = _colorFrom(p.getInt(_kCustomAccent));
    customBg.value = _colorFrom(p.getInt(_kCustomBg));
    customSurface.value = _colorFrom(p.getInt(_kCustomSurface));
    customTonal.value = _colorFrom(p.getInt(_kCustomTonal));

    bodyFont.value = p.getString(_kBodyFont) ?? 'Inter';
    bubbleStyle.value = switch (p.getString(_kBubbleStyle)) {
      // Legacy corner-style values were bubble variants — both become the
      // Bubbles layout. Fresh installs land on Default.
      'rounded' || 'flat' || 'bubbles' => 'bubbles',
      _ => 'default',
    };
    chatDensity.value = p.getString(_kChatDensity) ?? 'comfortable';
    chatBg.value = p.getString(_kChatBg) ?? 'default';
    loadingStyle.value = p.getString(_kLoadingStyle) ?? 'spinner';
    returnSends.value = p.getBool(_kReturnSends) ?? true;

    showTimestamps.value = p.getBool(_kShowTs) ?? false;
    timestampFormat.value = p.getString(_kTsFormat) ?? 'relative';
    dateDividers.value = p.getBool(_kDateDividers) ?? false;

    reduceMotion.value = p.getBool(_kReduceMotion) ?? false;
    hapticsEnabled.value = p.getBool(_kHaptics) ?? true;

    final storedTheme = p.getString(_kCodeTheme);
    codeTheme.value = _validCodeTheme(storedTheme) ? storedTheme! : 'dracula';
    agentAvatarPath.value = p.getString(_kAgentAvatar);

    notificationsEnabled.value = p.getBool(_kNotifMaster) ?? true;
    notifRunCompleted.value = p.getBool(_kNotifRunCompleted) ?? true;
    notifRunFailed.value = p.getBool(_kNotifRunFailed) ?? true;
    notifApprovalParked.value = p.getBool(_kNotifApprovalParked) ?? true;
    notifScheduleResults.value = p.getBool(_kNotifSchedule) ?? true;
    notifNightlyRepair.value = p.getBool(_kNotifNightly) ?? true;
    quietHoursEnabled.value = p.getBool(_kQuietOn) ?? false;
    quietStartMin.value = p.getInt(_kQuietStart) ?? 1320;
    quietEndMin.value = p.getInt(_kQuietEnd) ?? 420;
    mutedSessions.value = (p.getStringList(_kMutedSessions) ?? []).toSet();
    notifSoundEnabled.value = p.getBool(_kNotifSound) ?? true;
    _ready = true;
  }

  // Appearance setters (all bump the root rebuild tick).

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode.value = mode;
    _bump();
    (await SharedPreferences.getInstance())
        .setString(_kThemeMode, _modeName(mode));
  }

  Future<void> setTextScale(double scale) async {
    textScale.value = scale;
    _bump();
    (await SharedPreferences.getInstance()).setDouble(_kTextScale, scale);
  }

  Future<void> setCompactDensity(bool compact) async {
    compactDensity.value = compact;
    _bump();
    (await SharedPreferences.getInstance()).setBool(_kCompact, compact);
  }

  Future<void> setCustomAccent(Color? c) =>
      _setColor(_kCustomAccent, customAccent, c);
  Future<void> setCustomBg(Color? c) => _setColor(_kCustomBg, customBg, c);
  Future<void> setCustomSurface(Color? c) =>
      _setColor(_kCustomSurface, customSurface, c);
  Future<void> setCustomTonal(Color? c) =>
      _setColor(_kCustomTonal, customTonal, c);

  Future<void> resetCustomColors() async {
    await setCustomAccent(null);
    await setCustomBg(null);
    await setCustomSurface(null);
    await setCustomTonal(null);
  }

  Future<void> setBodyFont(String f) =>
      _setString(_kBodyFont, bodyFont, f);
  Future<void> setBubbleStyle(String s) =>
      _setString(_kBubbleStyle, bubbleStyle, s);
  Future<void> setChatDensity(String d) =>
      _setString(_kChatDensity, chatDensity, d);
  Future<void> setChatBg(String b) => _setString(_kChatBg, chatBg, b);
  Future<void> setLoadingStyle(String s) =>
      _setString(_kLoadingStyle, loadingStyle, s);
  Future<void> setTimestampFormat(String f) =>
      _setString(_kTsFormat, timestampFormat, f);

  Future<void> setReturnSends(bool v) =>
      _setBool(_kReturnSends, returnSends, v, bump: true);
  Future<void> setShowTimestamps(bool v) =>
      _setBool(_kShowTs, showTimestamps, v, bump: true);
  Future<void> setDateDividers(bool v) =>
      _setBool(_kDateDividers, dateDividers, v, bump: true);
  Future<void> setReduceMotion(bool v) =>
      _setBool(_kReduceMotion, reduceMotion, v, bump: true);
  Future<void> setHapticsEnabled(bool v) =>
      _setBool(_kHaptics, hapticsEnabled, v, bump: true);

  Future<void> setCodeTheme(String t) async {
    if (!_validCodeTheme(t)) return;
    await _setString(_kCodeTheme, codeTheme, t);
  }

  Future<void> setAgentAvatarPath(String? path) async {
    agentAvatarPath.value = path;
    _bump();
    final sp = await SharedPreferences.getInstance();
    if (path == null) {
      await sp.remove(_kAgentAvatar);
    } else {
      await sp.setString(_kAgentAvatar, path);
    }
  }

  static bool _validCodeTheme(String? t) =>
      t == 'github' || t == 'dracula' || t == 'atom-one-dark';

  // Notification setters (persisted; no root rebuild needed).

  Future<void> setNotificationsEnabled(bool v) =>
      _setBool(_kNotifMaster, notificationsEnabled, v);
  Future<void> setNotifRunCompleted(bool v) =>
      _setBool(_kNotifRunCompleted, notifRunCompleted, v);
  Future<void> setNotifRunFailed(bool v) =>
      _setBool(_kNotifRunFailed, notifRunFailed, v);
  Future<void> setNotifApprovalParked(bool v) =>
      _setBool(_kNotifApprovalParked, notifApprovalParked, v);
  Future<void> setNotifScheduleResults(bool v) =>
      _setBool(_kNotifSchedule, notifScheduleResults, v);
  Future<void> setNotifNightlyRepair(bool v) =>
      _setBool(_kNotifNightly, notifNightlyRepair, v);
  Future<void> setQuietHoursEnabled(bool v) =>
      _setBool(_kQuietOn, quietHoursEnabled, v);
  Future<void> setQuietStartMin(int v) async {
    quietStartMin.value = v;
    (await SharedPreferences.getInstance()).setInt(_kQuietStart, v);
  }

  Future<void> setQuietEndMin(int v) async {
    quietEndMin.value = v;
    (await SharedPreferences.getInstance()).setInt(_kQuietEnd, v);
  }

  Future<void> setNotifSoundEnabled(bool v) =>
      _setBool(_kNotifSound, notifSoundEnabled, v);

  Future<void> setSessionMuted(String id, bool muted) async {
    final next = Set<String>.of(mutedSessions.value);
    if (muted) {
      next.add(id);
    } else {
      next.remove(id);
    }
    mutedSessions.value = next;
    (await SharedPreferences.getInstance())
        .setStringList(_kMutedSessions, next.toList());
  }

  /// True when quiet hours are enabled and now falls inside them.
  /// [NotificationService.notify] calls this before firing.
  bool isQuietNow() {
    if (!quietHoursEnabled.value) return false;
    final now = DateTime.now();
    final m = now.hour * 60 + now.minute;
    final s = quietStartMin.value;
    final e = quietEndMin.value;
    if (s == e) return false;
    return s < e ? (m >= s && m < e) : (m >= s || m < e);
  }

  /// True when the session is muted. [NotificationService.notify]
  /// checks this at every emission point.
  bool isSessionMuted(String id) => mutedSessions.value.contains(id);

  Future<void> _setColor(
      String key, ValueNotifier<Color?> notifier, Color? value) async {
    notifier.value = value;
    _bump();
    final p = await SharedPreferences.getInstance();
    if (value == null) {
      await p.remove(key);
    } else {
      await p.setInt(key, value.value);
    }
  }

  Future<void> _setString(
      String key, ValueNotifier<String> notifier, String value) async {
    notifier.value = value;
    _bump();
    (await SharedPreferences.getInstance()).setString(key, value);
  }

  Future<void> _setBool(String key, ValueNotifier<bool> notifier, bool value,
      {bool bump = false}) async {
    notifier.value = value;
    if (bump) _bump();
    (await SharedPreferences.getInstance()).setBool(key, value);
  }

  static Color? _colorFrom(int? v) => v == null ? null : Color(v);

  static String _modeName(ThemeMode m) => switch (m) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };

  static ThemeMode _modeFrom(String? s) => switch (s) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
}
