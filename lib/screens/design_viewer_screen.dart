import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/drafthouse_gate.dart';
import '../services/pantheon_api.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/design_review_shared.dart';
import '../widgets/forms.dart';

/// Full-screen design-round viewer: swipeable [PageView], one page per
/// variant, with a gate-report bottom sheet and an action bar.
///
/// v1 renders round stills from `GET /api/uploads/:id` (memoized bytes —
/// no live stream; P5b swaps the substrate later). Actions ride the
/// verified `PantheonApi.sendRunMessage` channel:
///
/// - Approve → the exact handoff-trigger message from the skill contract.
/// - Request changes → steer/queue with the human's note.
/// - Pick variant → cycles pages; confirming sends the pick.
///
/// `isBusy` snapshots the run status at open time (`running`/`paused` ⇒
/// busy). A 409 TURN_IN_FLIGHT surfaces as a toast, same as the composer.
class DesignViewerScreen extends StatefulWidget {
  final DrafthouseGateBlock block;
  final PantheonApi api;
  final String runId;
  final bool isBusy;

  const DesignViewerScreen({
    super.key,
    required this.block,
    required this.api,
    required this.runId,
    this.isBusy = false,
  });

  @override
  State<DesignViewerScreen> createState() => _DesignViewerScreenState();
}

class _DesignViewerScreenState extends State<DesignViewerScreen> {
  late final PageController _pages;
  late int _page;
  bool _sending = false;

  DrafthouseGateBlock get _block => widget.block;

  @override
  void initState() {
    super.initState();
    _page = _block.pickedIndex;
    _pages = PageController(initialPage: _page);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  DrafthouseVariant get _current => _block.variants[_page];

  /// The currently shown variant is the human's pick when it differs from
  /// the judge's pick.
  bool get _differsFromJudge => _current.id != _block.judgePick;

  Future<void> _send(String message, {bool steer = false}) async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      final result = await widget.api.sendRunMessage(
        widget.runId,
        message,
        queue: widget.isBusy,
        steer: steer && widget.isBusy,
      );
      if (!mounted) return;
      toast(
        context,
        result.steered
            ? 'Steering the running turn…'
            : (result.queued
                ? 'Queued — sends when the turn settles.'
                : 'Sent.'),
      );
    } on PantheonTurnInFlightException {
      // Lost the idle→busy race between open and send.
      if (mounted) toast(context, 'A turn is already in flight — try again.');
    } catch (e) {
      if (mounted) toastError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _approve() async {
    await _send(drafthouseApproveMessage());
  }

  Future<void> _pickVariant() async {
    // Same channel as steering: the human's pick overrides the judge's.
    await _send(drafthousePickVariantMessage(_current.id), steer: true);
  }

  Future<void> _requestChanges() async {
    final text = await _changesSheet();
    if (text == null || text.trim().isEmpty || !mounted) return;
    await _send(
      drafthouseRequestChangesMessage(_block.round, _current.id, text.trim()),
      steer: true,
    );
  }

  /// Bottom sheet with a single text field for the human's change note.
  Future<String?> _changesSheet() {
    final controller = TextEditingController();
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: P.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 12,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: P.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Request changes · round ${_block.round}, variant ${_current.id.toUpperCase()}',
                style: PT.sectionTitle.copyWith(color: P.ink),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                maxLines: 4,
                minLines: 2,
                style: PT.body.copyWith(color: P.ink),
                decoration: InputDecoration(
                  hintText: 'What should change?',
                  hintStyle: PT.body.copyWith(color: P.inkFaint),
                  filled: true,
                  fillColor: P.tonal,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(P.r12),
                    borderSide: BorderSide(color: P.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(P.r12),
                    borderSide: BorderSide(color: P.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(P.r12),
                    borderSide: BorderSide(color: P.accent),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              GradientButton(
                label: _sending ? 'Sending…' : 'Send feedback',
                onTap: _sending
                    ? null
                    : () => Navigator.of(sheetContext).pop(controller.text),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: P.surface,
      appBar: AppBar(
        backgroundColor: P.surface,
        foregroundColor: P.ink,
        elevation: 0,
        title: Text(
          '${_block.artifact} · round ${_block.round}',
          style: PT.appBarTitle.copyWith(color: P.ink),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: DesignStatusPill(needsHuman: _block.needsHuman),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pages,
              itemCount: _block.variants.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (context, i) =>
                  _VariantPage(block: _block, index: i, api: widget.api),
            ),
          ),
          _VariantDots(
            block: _block,
            current: _page,
            onTap: (i) => _pages.animateToPage(
              i,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
            ),
          ),
          const SizedBox(height: 4),
          if (_differsFromJudge)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Use variant ${_current.displayLabel()} instead of the judge pick (${_block.judgePick.toUpperCase()})?',
                      style: PT.small.copyWith(color: P.inkSecondary),
                    ),
                  ),
                  const SizedBox(width: 8),
                  PillButton(
                    label: _sending ? 'Sending…' : 'Confirm',
                    onTap: _sending ? null : _pickVariant,
                    color: P.warn,
                  ),
                ],
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GradientButton(
                    label: _sending ? 'Sending…' : 'Approve',
                    onTap: _sending ? null : _approve,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TonalButton(
                          label: 'Request changes',
                          onTap: _sending ? null : _requestChanges,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TonalButton(
                          label: 'Gate report',
                          onTap: () => showDesignGateSheet(context,
                              block: _block),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TonalButton(
                          label: 'Pick variant',
                          onTap: _sending ? null : () => _pages.nextPage(
                                duration:
                                    const Duration(milliseconds: 250),
                                curve: Curves.easeOut,
                              ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VariantPage extends StatelessWidget {
  final DrafthouseGateBlock block;
  final int index;
  final PantheonApi api;

  const _VariantPage(
      {required this.block, required this.index, required this.api});

  @override
  Widget build(BuildContext context) {
    final variant = block.variants[index];
    return FutureBuilder<Uint8List?>(
      future: DesignStillCache.stillBytes(api, variant.still),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(
              child: CircularProgressIndicator.adaptive());
        }
        if (snap.data == null) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.broken_image_outlined,
                    size: 40, color: P.inkFaint),
                const SizedBox(height: 8),
                Text("Couldn't load this still.",
                    style: PT.small.copyWith(color: P.inkSecondary)),
              ],
            ),
          );
        }
        return InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: Center(
            child: Image.memory(snap.data!, fit: BoxFit.contain),
          ),
        );
      },
    );
  }
}

class _VariantDots extends StatelessWidget {
  final DrafthouseGateBlock block;
  final int current;
  final ValueChanged<int> onTap;

  const _VariantDots(
      {required this.block, required this.current, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < block.variants.length; i++) ...[
            GestureDetector(
              onTap: () => onTap(i),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: i == current ? P.accentSoft : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: i == current ? P.accent : P.border,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      block.variants[i].displayLabel(),
                      style: PT.small.copyWith(
                        color: i == current ? P.accent : P.inkSecondary,
                        fontWeight: i == current
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                    if (block.variants[i].id == block.judgePick) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.verified_rounded,
                          size: 12, color: P.accent),
                    ],
                  ],
                ),
              ),
            ),
            if (i < block.variants.length - 1) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}
