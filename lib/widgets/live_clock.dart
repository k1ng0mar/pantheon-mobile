import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';

/// Self-ticking live-turn clock: the quiet "Working for 1m 9s" row at the
/// end of a running chat.
///
/// The row owns its once-a-second timer so the elapsed label repaints in
/// isolation. The owning screen rebuilds the transcript on poll events,
/// never on the clock tick: a running turn must not rebuild the whole
/// message list once a second. Elapsed is always derived from the absolute
/// [sinceMs] anchor, so a rebuilt or recycled row never drifts or resets
/// the count.
class LiveClockRow extends StatefulWidget {
  final int sinceMs;

  const LiveClockRow({super.key, required this.sinceMs});

  /// "Working for 5s" / "Working for 1m 5s". Pure so the format is
  /// testable without a running clock.
  static String label(int elapsedSeconds) {
    final s = elapsedSeconds < 0 ? 0 : elapsedSeconds;
    return s >= 60
        ? 'Working for ${s ~/ 60}m ${s % 60}s'
        : 'Working for ${s}s';
  }

  @override
  State<LiveClockRow> createState() => _LiveClockRowState();
}

class _LiveClockRowState extends State<LiveClockRow> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s =
        ((DateTime.now().millisecondsSinceEpoch - widget.sinceMs) / 1000)
            .floor();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 2),
      child: Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text(LiveClockRow.label(s),
              style: PT.small.copyWith(color: P.inkSecondary)),
        ],
      ),
    );
  }
}
