import 'dart:async';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/notification_service.dart';
import '../services/pantheon_api.dart';
import '../theme.dart';
import '../widgets/approval_actions.dart';
import '../widgets/buttons.dart';
import '../widgets/forms.dart';
import '../widgets/pantheon_card.dart';
import '../widgets/states.dart';

class ApprovalsScreen extends StatefulWidget {
  final PantheonApi api;
  final ValueNotifier<int> pendingApprovals;

  const ApprovalsScreen(
      {super.key, required this.api, required this.pendingApprovals});

  @override
  State<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends State<ApprovalsScreen> {
  Future<List<Approval>>? _future;
  final Set<String> _busy = {};
  final Set<String> _leaving = {};

  /// Approvals can arrive from the dashboard, the TUI, or another
  /// device while this screen sits open: re-fetch periodically so a
  /// decision can't be made against a stale list.
  Timer? _pollTimer;

  /// Approval ids already seen: the poller notifies only for newly
  /// parked ones.
  final Set<String> _seenApprovalIds = {};

  @override
  void initState() {
    super.initState();
    _load();
    _pollTimer =
        Timer.periodic(const Duration(seconds: 10), (_) => _quietRefresh());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _load() {
    setState(() {
      _leaving.clear();
      _future = widget.api.approvals().then((list) {
        widget.pendingApprovals.value = list.length;
        // Seed the seen set so the initial load doesn't notify for
        // approvals that were already parked.
        _seenApprovalIds
          ..clear()
          ..addAll(list.map((a) => a.id));
        return list;
      });
    });
  }

  /// Refresh the list without the loading skeleton: fetch first, then
  /// swap in an already-completed future. Skipped while a decision is
  /// in flight (its completion refreshes anyway) and silent on failure
  /// — the next tick retries and the manual refresh button stays.
  Future<void> _quietRefresh() async {
    if (!mounted || _busy.isNotEmpty) return;
    try {
      final list = await widget.api.approvals();
      if (!mounted) return;
      widget.pendingApprovals.value = list.length;
      // Alertable event: newly parked approvals. The delivery path
      // consults the stored notification prefs before showing anything.
      for (final a in list) {
        if (_seenApprovalIds.add(a.id)) {
          unawaited(NotificationService.instance.notify(
            event: NotificationService.eventApprovalParked,
            sessionId: a.runId.isNotEmpty ? a.runId : null,
            title: 'Approval needed',
            body: '${a.displayRun} is parked waiting for your decision.',
          ));
        }
      }
      setState(() => _future = Future.value(list));
    } catch (_) {}
  }

  Future<void> _decide(Approval a, bool grant) async {
    // Granting with offered tiers: pick the tier in-sheet. Deny and the
    // tierless fallback keep the plain confirm sheet.
    final tiers = grant ? a.availableTiers : const <String>[];
    String? mode;
    if (tiers.isEmpty) {
      final ok = await showPSheet<bool>(
        context,
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SheetHandle(),
                const SizedBox(height: 8),
                Text(grant ? 'Grant this approval?' : 'Deny this approval?',
                    style: PT.sectionTitle),
                const SizedBox(height: 8),
                Text('${a.tool ?? 'tool'} on "${a.displayRun}"',
                    style: PT.small),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: TonalButton(
                          label: 'Cancel',
                          onTap: () => Navigator.pop(context, false)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GradientButton(
                        label: grant ? 'Grant' : 'Deny',
                        onTap: () => Navigator.pop(context, true),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      if (ok != true || !mounted) return;
    } else {
      final picked = await showPSheet<String>(
        context,
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SheetHandle(),
                const SizedBox(height: 8),
                const Text('Choose how to grant', style: PT.sectionTitle),
                const SizedBox(height: 8),
                Text('${a.tool ?? 'tool'} on "${a.displayRun}"',
                    style: PT.small),
                const SizedBox(height: 16),
                for (final tier in tiers) ...[
                  _tierRow(
                      context, tier, () => Navigator.pop(context, tier)),
                  const SizedBox(height: 8),
                ],
                TonalButton(
                    label: 'Cancel',
                    onTap: () => Navigator.pop(context)),
              ],
            ),
          ),
        ),
      );
      if (picked == null || !mounted) return;
      mode = picked;
    }
    setState(() => _busy.add(a.id));
    try {
      await widget.api.decideApproval(a.id, grant, mode: mode);
      if (!mounted) return;
      // Animate the card out, then refresh.
      setState(() {
        _leaving.add(a.id);
        _busy.remove(a.id);
      });
      await Future.delayed(const Duration(milliseconds: 280));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_decideToast(grant, mode))),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e')),
      );
      setState(() => _busy.remove(a.id));
    }
  }

  String _decideToast(bool grant, String? mode) {
    if (!grant) return 'Approval denied.';
    return switch (mode) {
      'session' => 'Granted for this session.',
      'always' => 'Won\'t ask for this again.',
      _ => 'Approval granted.',
    };
  }

  /// One grant-tier row in the tier picker sheet: label + hint, taps
  /// through to grant with that tier.
  Widget _tierRow(BuildContext context, String tier, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: P.tonal,
          borderRadius: BorderRadius.circular(P.r16),
          border: Border.all(color: P.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ApprovalActions.tierLabel(tier), style: PT.rowTitle),
                  const SizedBox(height: 2),
                  Text(ApprovalActions.tierHint(tier), style: PT.small),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(Icons.chevron_right_rounded,
                color: P.inkSecondary, size: 22, weight: 1.6),
          ],
        ),
      ),
    );
  }

  /// Standing grants: the durable "always" grants, oldest first, each
  /// revocable. Stale backends (no `/api/approvals/grants`) get the
  /// upgrade toast instead of an error sheet.
  Future<void> _showGrants() async {
    List<StandingGrant> grants;
    try {
      grants = await widget.api.standingGrants();
    } on PantheonStaleBackendException catch (e) {
      if (mounted) toast(context, e.toString());
      return;
    } catch (e) {
      if (mounted) toast(context, 'Failed: $e');
      return;
    }
    if (!mounted) return;
    await showPSheet(
      context,
      SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: StatefulBuilder(
            builder: (context, setSheetState) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SheetHandle(),
                const SizedBox(height: 8),
                const Text('Standing grants', style: PT.sectionTitle),
                const SizedBox(height: 8),
                const Text(
                  '"Always allow" decisions live here. Revoke one and the '
                  'next identical request parks for approval again.',
                  style: PT.small,
                ),
                const SizedBox(height: 16),
                if (grants.isEmpty)
                  const Text('No standing grants yet.', style: PT.small)
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: grants.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final g = grants[i];
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: P.tonal,
                            borderRadius:
                                BorderRadius.circular(P.r16),
                            border: Border.all(color: P.border),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(g.tool, style: PT.rowTitle),
                                    if (g.argsPreview.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(g.argsPreview,
                                          style: PT.monoSm,
                                          maxLines: 2,
                                          overflow:
                                              TextOverflow.ellipsis),
                                    ],
                                    const SizedBox(height: 2),
                                    Text(
                                        'granted ${timeAgo(g.createdMs)}',
                                        style: PT.faint),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    weight: 1.6),
                                color: P.err,
                                tooltip: 'Revoke',
                                onPressed: () async {
                                  try {
                                    await widget.api
                                        .revokeGrant(g.id);
                                    setSheetState(() =>
                                        grants.removeAt(i));
                                    if (context.mounted) {
                                      toast(context,
                                          'Grant revoked.');
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      toast(context,
                                          'Failed: $e');
                                    }
                                  }
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Approvals'),
        actions: [
          IconButton(
            icon: const Icon(Icons.key_rounded,
                color: P.inkSecondary, weight: 1.6),
            tooltip: 'Standing grants',
            onPressed: _showGrants,
          ),
          IconButton(
            icon:  Icon(Icons.refresh_rounded,
                color: P.inkSecondary, weight: 1.6),
            onPressed: _load,
          ),
        ],
      ),
      body: FutureBuilder<List<Approval>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return _skeleton();
          }
          if (snap.hasError) {
            return EmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'Couldn\'t load approvals',
              body: snap.error.toString(),
              ctaLabel: 'Retry',
              onCta: _load,
            );
          }
          final list = snap.data!;
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.check_circle_outline_rounded,
              title: 'All clear',
              body: 'No runs are waiting on your decision right now.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => _load(),
            color: P.accent,
            backgroundColor: P.surface,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              itemCount: list.length,
              itemBuilder: (context, i) =>
                  StaggerItem(index: i, child: _card(list[i])),
            ),
          );
        },
      ),
    );
  }

  Widget _card(Approval a) {
    final busy = _busy.contains(a.id);
    final leaving = _leaving.contains(a.id);
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 260),
      opacity: leaving ? 0 : 1,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeIn,
        offset: leaving ? const Offset(0.6, 0) : Offset.zero,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          // Nyx signature: error-colored border, uppercase kicker, pill actions.
          child: PCard(
            borderColor: P.err.withValues(alpha: 0.55),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('APPROVAL NEEDED',
                    style: PT.overline.copyWith(color: P.err)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: P.warn.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(P.r12),
                      ),
                      child: const Icon(Icons.rule_rounded,
                          color: P.warn, size: 20, weight: 1.6),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(a.tool ?? 'tool call', style: PT.rowTitle),
                          const SizedBox(height: 2),
                          Text(a.displayRun,
                              style: PT.meta,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  ],
                ),
                if (a.args != null && a.args!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: P.bg,
                      borderRadius: BorderRadius.circular(P.r12),
                      border: Border.all(color: P.border),
                    ),
                    child: Text(a.args!,
                        style: PT.mono.copyWith(fontSize: 12),
                        maxLines: 6,
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
                const SizedBox(height: 6),
                Text('requested ${timeAgo(a.runCreatedMs)}', style: PT.faint),
                const SizedBox(height: 14),
                if (busy)
                   SizedBox(
                    height: 42,
                    child: Center(
                        child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: P.accent))),
                  )
                else
                  ApprovalActions(
                    tiers: a.availableTiers,
                    denyFilled: false,
                    onDeny: () => _decide(a, false),
                    // The tier choice is confirmed in-sheet by _decide.
                    onGrant: (_) => _decide(a, true),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _skeleton() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: 3,
      itemBuilder: (_, __) => const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: Shimmer(width: double.infinity, height: 190, radius: 16),
      ),
    );
  }
}
