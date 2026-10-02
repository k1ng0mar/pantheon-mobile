import 'package:flutter/material.dart';

import '../models/models.dart';
import '../screens/session_detail_screen.dart';
import '../services/pantheon_api.dart';
import '../theme.dart';
import 'buttons.dart';
import 'forms.dart';
import 'states.dart';

/// The shared session-detail transition: 280ms slide-in from the right
/// with a fade (220ms reverse). Every push of [SessionDetailScreen] goes
/// through here so the motion stays identical across the app.
Route<T> buildDetailRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, anim, __, child) {
      final slide = Tween<Offset>(
              begin: const Offset(0.08, 0), end: Offset.zero)
          .animate(
              CurvedAnimation(parent: anim, curve: Curves.easeOutCubic));
      final fade = Tween<double>(begin: 0, end: 1).animate(
          CurvedAnimation(parent: anim, curve: Curves.easeOut));
      return SlideTransition(
          position: slide,
          child: FadeTransition(opacity: fade, child: child));
    },
  );
}

/// Shared "start a new chat" sheet: opening message (+ optional title),
/// `createRun`, then straight into the detail view.
///
/// One implementation for both call sites that used to carry their own
/// near-identical copy: the Sessions tab FAB and the detail screen's
/// `/new` slash command.
///
/// [agentName] is the caller's active agent name (the same `_agentName`
/// state the chat screens feed from the config's active agent), so the
/// prompt never hardcodes a product or agent name.
Future<void> showNewChatSheet(BuildContext context, PantheonApi api,
    {required String agentName}) async {
  final messageCtrl = TextEditingController();
  final titleCtrl = TextEditingController();
  var busy = false;
  try {
    final created = await showPSheet<PantheonRun>(
      context,
      StatefulBuilder(
        builder: (ctx, setSheet) {
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  20, 8, 20, 24 + MediaQuery.of(ctx).viewInsets.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SheetHandle(),
                  const SizedBox(height: 8),
                  Text('New chat', style: PT.sectionTitle),
                  const SizedBox(height: 4),
                  Text('Your first message starts the session.',
                      style: PT.meta),
                  const SizedBox(height: 16),
                  TextField(
                    controller: messageCtrl,
                    autofocus: true,
                    minLines: 2,
                    maxLines: 5,
                    style: PT.body,
                    decoration: InputDecoration(
                      hintText: 'What should $agentName do?',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: titleCtrl,
                    style: PT.body,
                    decoration: const InputDecoration(
                      hintText: 'Title (optional)',
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: TonalButton(
                            label: 'Cancel',
                            onTap: () => Navigator.pop(ctx)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GradientButton(
                          label: busy ? 'Starting…' : 'Start',
                          onTap: busy
                              ? null
                              : () async {
                                  final msg = messageCtrl.text.trim();
                                  if (msg.isEmpty) return;
                                  setSheet(() => busy = true);
                                  try {
                                    final run = await api.createRun(
                                      message: msg,
                                      title: titleCtrl.text.trim().isEmpty
                                          ? null
                                          : titleCtrl.text.trim(),
                                    );
                                    if (ctx.mounted) {
                                      Navigator.pop(ctx, run);
                                    }
                                  } catch (e) {
                                    if (ctx.mounted) {
                                      setSheet(() => busy = false);
                                      toastError(ctx, e);
                                    }
                                  }
                                },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (created == null || !context.mounted) return;
    await Navigator.of(context).push(
      buildDetailRoute(SessionDetailScreen(api: api, runId: created.id)),
    );
  } finally {
    messageCtrl.dispose();
    titleCtrl.dispose();
  }
}
