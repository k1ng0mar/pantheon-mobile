import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/drafthouse_gate.dart';
import '../screens/design_viewer_screen.dart';
import '../services/pantheon_api.dart';
import '../theme.dart';
import 'design_review_shared.dart';

/// Artifact card for a design round: rendered below an assistant message
/// that carries a ````drafthouse-gate` fenced block.
///
/// Chrome mirrors [LinkPreviewCard] exactly: [P.tonal] fill, [P.r12],
/// [P.border]. The 16:9 thumbnail is the judge pick's still; still bytes
/// are memoized per session in [DesignStillCache] so rebuilds and the
/// viewer never refetch. Tapping opens the full-screen
/// [DesignViewerScreen].
class DesignReviewCard extends StatefulWidget {
  final DrafthouseGateBlock block;
  final PantheonApi api;
  final String runId;

  /// True when the run's turn is in flight (`running`/`paused`) — design
  /// actions then queue/steer instead of starting a new turn.
  final bool isBusy;

  const DesignReviewCard({
    super.key,
    required this.block,
    required this.api,
    required this.runId,
    this.isBusy = false,
  });

  @override
  State<DesignReviewCard> createState() => _DesignReviewCardState();
}

class _DesignReviewCardState extends State<DesignReviewCard> {
  bool _visible = false;
  bool _imageOk = true;

  @override
  Widget build(BuildContext context) {
    final block = widget.block;
    final pick = block.pickedVariant;
    return AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: const Duration(milliseconds: 250),
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: InkWell(
          borderRadius: BorderRadius.circular(P.r12),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => DesignViewerScreen(
                block: block,
                api: widget.api,
                runId: widget.runId,
                isBusy: widget.isBusy,
              ),
            ),
          ),
          child: Container(
            decoration: BoxDecoration(
              color: P.tonal,
              borderRadius: BorderRadius.circular(P.r12),
              border: Border.all(color: P.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                FutureBuilder<Uint8List?>(
                  future:
                      DesignStillCache.stillBytes(widget.api, pick.still),
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done ||
                        snap.data == null) {
                      return const SizedBox.shrink();
                    }
                    if (!_visible) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() => _visible = true);
                      });
                    }
                    if (!_imageOk) return const SizedBox.shrink();
                    return AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Image.memory(
                        snap.data!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stack) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) setState(() => _imageOk = false);
                          });
                          return const SizedBox.shrink();
                        },
                      ),
                    );
                  },
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Design · ${block.artifact} · round ${block.round}',
                              style: PT.body.copyWith(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: P.ink,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          DesignStatusPill(needsHuman: block.needsHuman),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        block.gateSummary(),
                        style: PT.small.copyWith(color: P.inkSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
