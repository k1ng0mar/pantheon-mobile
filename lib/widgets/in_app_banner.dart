import 'dart:async';

import 'package:flutter/material.dart';

import '../services/notification_service.dart';
import '../theme.dart';

/// One in-app notice: banner/overlay only, local only — no push.
class InAppNotice {
  final String title;
  final String body;
  final VoidCallback? onTap;

  InAppNotice({required this.title, required this.body, this.onTap});
}

/// In-app notification controller. The banner slides down over the
/// current tab and auto-dismisses; tapping it runs [InAppNotice.onTap].
///
/// Delivery respects the stored notification preferences via
/// [NotificationService.shouldNotify]: the master switch, the per-event
/// toggle, quiet hours, and per-session mute all suppress the banner.
class InAppBanner {
  InAppBanner._();

  static final ValueNotifier<InAppNotice?> current = ValueNotifier(null);
  static Timer? _timer;

  /// Show an approval banner for a newly parked approval.
  static void showApproval({
    required String title,
    required String body,
    String? sessionId,
    VoidCallback? onTap,
    Duration duration = const Duration(seconds: 6),
  }) {
    if (!NotificationService.instance.shouldNotify(
      event: NotificationService.eventApprovalParked,
      sessionId: sessionId,
    )) {
      return;
    }
    _timer?.cancel();
    current.value = InAppNotice(title: title, body: body, onTap: onTap);
    _timer = Timer(duration, () => current.value = null);
  }

  static void dismiss() {
    _timer?.cancel();
    current.value = null;
  }
}

/// Host for the banner: place once, pinned to the top of the app shell.
class InAppBannerHost extends StatelessWidget {
  const InAppBannerHost({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<InAppNotice?>(
      valueListenable: InAppBanner.current,
      builder: (context, notice, _) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        transitionBuilder: (child, anim) => SlideTransition(
          position:
              Tween(begin: const Offset(0, -1), end: Offset.zero).animate(
            CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
        child: notice == null
            ? const SizedBox.shrink(key: ValueKey('none'))
            : _banner(context, notice),
      ),
    );
  }

  Widget _banner(BuildContext context, InAppNotice notice) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Material(
          key: const ValueKey('banner'),
          color: P.surface,
          elevation: 8,
          borderRadius: BorderRadius.circular(P.r16),
          child: InkWell(
            onTap: notice.onTap,
            borderRadius: BorderRadius.circular(P.r16),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(P.r16),
                border:
                    Border.all(color: P.warn.withValues(alpha: 0.55)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: P.warn.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(P.r12),
                    ),
                    child: const Icon(Icons.rule_rounded,
                        color: P.warn, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(notice.title,
                            style: PT.rowTitle.copyWith(fontSize: 14)),
                        const SizedBox(height: 2),
                        Text(notice.body,
                            style: PT.meta,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.close_rounded,
                        size: 16, color: P.inkSecondary),
                    onPressed: InAppBanner.dismiss,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
