import 'package:flutter/material.dart';

import '../models/pantheon_run.dart';
import '../services/app_preferences.dart';
import '../services/pantheon_api.dart';
import '../theme.dart';
import '../widgets/chips.dart';
import '../widgets/pantheon_card.dart';
import '../widgets/states.dart';

/// Notification preferences.
///
/// Persisted locally and ready to drive a delivery path, but: the app has
/// no push or local-notification delivery wired yet (no FCM/APNs/local
/// notifications package), so nothing actually fires today. Quiet hours,
/// per-session mute, and sound prefs are stored now and the delivery layer
/// will consult `isQuietNow()`, `isSessionMuted(id)`, and
/// `notifSoundEnabled` when it lands.
class NotificationsScreen extends StatelessWidget {
  final PantheonApi api;

  const NotificationsScreen({super.key, required this.api});

  @override
  Widget build(BuildContext context) {
    final prefs = AppPreferences.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
            child: Text(
              'Choose what the app may tell you about. '
              'Push delivery is not wired yet, so these preferences are '
              'stored now and will take effect when delivery lands.',
              style: PT.meta.copyWith(height: 1.4),
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: prefs.notificationsEnabled,
            builder: (_, enabled, __) => PRowCard(
              rows: [
                PRow(
                  title: 'Notifications',
                  subtitle: 'Master switch for all alerts',
                  dotColor: P.accent,
                  onTap: () => prefs.setNotificationsEnabled(!enabled),
                  trailing: Switch(
                      value: enabled, onChanged: prefs.setNotificationsEnabled),
                ),
              ],
            ),
          ),
          const Overline('Events'),
          PRowCard(
            rows: [
              _eventRow(prefs.notifRunCompleted, prefs.setNotifRunCompleted,
                  'Run completed', 'A turn finished successfully', P.ok),
              _eventRow(prefs.notifRunFailed, prefs.setNotifRunFailed,
                  'Run failed or canceled', 'A turn ended in error', P.err),
              _eventRow(
                  prefs.notifApprovalParked,
                  prefs.setNotifApprovalParked,
                  'Approval parked',
                  'Informational only — never a phone approval loop',
                  P.warn),
              _eventRow(
                  prefs.notifScheduleResults,
                  prefs.setNotifScheduleResults,
                  'Scheduled task results',
                  'When a cron or scheduled run reports back',
                  P.info),
              _eventRow(
                  prefs.notifNightlyRepair,
                  prefs.setNotifNightlyRepair,
                  'Nightly repair reports',
                  'What the nightly loop fixed',
                  P.accent),
            ],
          ),
          const Overline('Quiet hours'),
          ValueListenableBuilder<bool>(
            valueListenable: prefs.quietHoursEnabled,
            builder: (_, enabled, __) => PRowCard(
              rows: [
                PRow(
                  title: 'Quiet hours',
                  subtitle: 'No notifications during this window',
                  dotColor: P.inkFaint,
                  onTap: () => prefs.setQuietHoursEnabled(!enabled),
                  trailing: Switch(
                      value: enabled,
                      onChanged: prefs.setQuietHoursEnabled),
                ),
                PRow(
                  title: 'Start',
                  dotColor: P.inkFaint,
                  onTap: () => _pickTime(context, true),
                  trailing: ValueListenableBuilder<int>(
                    valueListenable: prefs.quietStartMin,
                    builder: (_, mins, __) =>
                        Text(_fmtTime(context, mins), style: PT.mono),
                  ),
                ),
                PRow(
                  title: 'End',
                  dotColor: P.inkFaint,
                  onTap: () => _pickTime(context, false),
                  trailing: ValueListenableBuilder<int>(
                    valueListenable: prefs.quietEndMin,
                    builder: (_, mins, __) =>
                        Text(_fmtTime(context, mins), style: PT.mono),
                  ),
                ),
              ],
            ),
          ),
          const Overline('Sounds'),
          ValueListenableBuilder<bool>(
            valueListenable: prefs.notifSoundEnabled,
            builder: (_, sound, __) => PRowCard(
              rows: [
                PRow(
                  title: 'Notification sound',
                  subtitle: 'Tone choice arrives with the delivery path',
                  dotColor: P.accent,
                  onTap: () => prefs.setNotifSoundEnabled(!sound),
                  trailing: Switch(
                      value: sound, onChanged: prefs.setNotifSoundEnabled),
                ),
              ],
            ),
          ),
          const Overline('Sessions'),
          PRowCard(
            rows: [
              PRow(
                title: 'Muted sessions',
                dotColor: P.warn,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => _MutedSessionsScreen(api: api)),
                ),
                trailing: ValueListenableBuilder<Set<String>>(
                  valueListenable: prefs.mutedSessions,
                  builder: (_, muted, __) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${muted.length} muted', style: PT.monoSm),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right_rounded,
                          size: 18, color: P.inkFaint),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
            child: Text(
              'Quiet hours, session mutes, and the sound toggle are checked '
              'by the delivery path before anything fires.',
              style: PT.faint.copyWith(height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  PRow _eventRow(ValueNotifier<bool> notifier,
      Future<void> Function(bool) setter, String title, String subtitle,
      [Color? dot]) {
    return PRow(
      title: title,
      subtitle: subtitle,
      dotColor: dot,
      onTap: () => setter(!notifier.value),
      trailing: ValueListenableBuilder<bool>(
        valueListenable: notifier,
        builder: (_, v, __) => Switch(value: v, onChanged: setter),
      ),
    );
  }

  static String _fmtTime(BuildContext context, int mins) =>
      TimeOfDay(hour: mins ~/ 60, minute: mins % 60).format(context);

  static Future<void> _pickTime(BuildContext context, bool isStart) async {
    final prefs = AppPreferences.instance;
    final cur = isStart ? prefs.quietStartMin.value : prefs.quietEndMin.value;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: cur ~/ 60, minute: cur % 60),
    );
    if (t == null) return;
    final mins = t.hour * 60 + t.minute;
    if (isStart) {
      await prefs.setQuietStartMin(mins);
    } else {
      await prefs.setQuietEndMin(mins);
    }
  }
}

/// Pick which sessions never fire notifications.
class _MutedSessionsScreen extends StatelessWidget {
  final PantheonApi api;

  const _MutedSessionsScreen({required this.api});

  @override
  Widget build(BuildContext context) {
    final prefs = AppPreferences.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Muted sessions')),
      body: FutureBuilder<List<PantheonRun>>(
        future: api.runs(limit: 200),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const LoadingState(label: 'Loading sessions…');
          }
          if (snap.hasError) {
            return ErrorState(
                message: '${snap.error}',
                onRetry: () => (context as Element).markNeedsBuild());
          }
          final runs = snap.data ?? [];
          if (runs.isEmpty) {
            return const EmptyState(
              icon: Icons.notifications_off_outlined,
              title: 'No sessions',
              body: 'Sessions you mute will be listed here.',
            );
          }
          return ValueListenableBuilder<Set<String>>(
            valueListenable: prefs.mutedSessions,
            builder: (_, muted, __) => ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: runs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final r = runs[i];
                final isMuted = muted.contains(r.id);
                return PCard(
                  padding: EdgeInsets.zero,
                  child: PRow(
                    title: r.displayTitle,
                    subtitle: r.id.length > 8 ? r.id.substring(0, 8) : r.id,
                    dotColor: isMuted ? P.warn : P.inkFaint,
                    onTap: () => prefs.setSessionMuted(r.id, !isMuted),
                    trailing: Switch(
                      value: isMuted,
                      onChanged: (v) => prefs.setSessionMuted(r.id, v),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
