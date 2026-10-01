import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'app_preferences.dart';

/// Local-notification delivery for the app's alertable events.
///
/// Every emission goes through [notify], which consults the stored
/// notification preferences *before* showing anything: the master
/// switch, the per-event toggle, quiet hours ([AppPreferences.isQuietNow]),
/// and per-session mute ([AppPreferences.isSessionMuted]). Nothing fires
/// when the user has not opted in.
///
/// Call sites are the existing event ingress points: the run poller in
/// the session detail screen (run completed / failed, approval parked)
/// and the approvals screen poller (new parked approvals). Schedule and
/// nightly events expose the same toggles but have no polling ingress
/// point yet, so they have no call sites — wiring them needs a
/// background poller.
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  /// Event kinds, matching the toggles on the notifications screen.
  static const eventRunCompleted = 'run_completed';
  static const eventRunFailed = 'run_failed';
  static const eventApprovalParked = 'approval_parked';
  static const eventScheduleResults = 'schedule_results';
  static const eventNightlyRepair = 'nightly_repair';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> _ensureInit() async {
    if (_ready) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    const settings =
        InitializationSettings(android: android, iOS: ios);
    await _plugin.initialize(settings);
    _ready = true;
  }

  bool _eventEnabled(AppPreferences prefs, String event) {
    switch (event) {
      case eventRunCompleted:
        return prefs.notifRunCompleted.value;
      case eventRunFailed:
        return prefs.notifRunFailed.value;
      case eventApprovalParked:
        return prefs.notifApprovalParked.value;
      case eventScheduleResults:
        return prefs.notifScheduleResults.value;
      case eventNightlyRepair:
        return prefs.notifNightlyRepair.value;
      default:
        return false;
    }
  }

  /// Preference gate shared by every delivery path: master switch,
  /// per-event toggle, quiet hours, per-session mute. Returns false
  /// when nothing should be shown.
  bool shouldNotify({required String event, String? sessionId}) {
    final prefs = AppPreferences.instance;
    if (!prefs.notificationsEnabled.value) return false;
    if (!_eventEnabled(prefs, event)) return false;
    if (prefs.isQuietNow()) return false;
    if (sessionId != null && prefs.isSessionMuted(sessionId)) return false;
    return true;
  }

  /// Show a local notification for [event] unless a preference suppresses
  /// it. [sessionId] is the run id, used for per-session mute; null when
  /// the event is not tied to a session.
  Future<void> notify({
    required String event,
    String? sessionId,
    required String title,
    required String body,
  }) async {
    if (!shouldNotify(event: event, sessionId: sessionId)) return;
    final prefs = AppPreferences.instance;
    final sound = prefs.notifSoundEnabled.value;
    await _ensureInit();
    await _plugin.show(
      _idFor(event, sessionId),
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'pantheon_events',
          'Pantheon events',
          channelDescription:
              'Run, approval, schedule and nightly alerts',
          playSound: sound,
          enableVibration: sound,
        ),
        iOS: DarwinNotificationDetails(presentSound: sound),
      ),
    );
  }

  /// Stable notification id per event+session so repeats replace rather
  /// than stack.
  int _idFor(String event, String? sessionId) =>
      (event.hashCode ^ (sessionId?.hashCode ?? 0)) & 0x7fffffff;
}
