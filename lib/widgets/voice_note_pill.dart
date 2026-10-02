import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../services/app_preferences.dart';
import '../theme.dart';
import 'forms.dart';

/// Voice-note recording pill: `[trash] 0:03 ▮▮▮▮▯▯ [send]`.
///
/// Replaces the composer row while recording. Owns the recording session on
/// an [AudioRecorder] the parent created (and already permission-checked);
/// the parent disposes the recorder after [onDiscard]/[onFinished] fire.
///
/// - Trash cancels the recording (file deleted) and calls [onDiscard].
/// - Send stops the recorder and calls [onFinished] with the file path.
/// - Recordings auto-stop at [maxSeconds]: WAV 16 kHz mono 16-bit is
///   ~32 KB/s, so a full 3 minutes stays under the app's 8 MiB
///   pre-upload check (the gateway itself allows up to 12 MiB).
class VoiceNotePill extends StatefulWidget {
  const VoiceNotePill({
    super.key,
    required this.recorder,
    required this.onDiscard,
    required this.onFinished,
  });

  final AudioRecorder recorder;
  final VoidCallback onDiscard;
  final ValueChanged<String> onFinished;

  static const maxSeconds = 180;

  @override
  State<VoiceNotePill> createState() => _VoiceNotePillState();
}

class _VoiceNotePillState extends State<VoiceNotePill> {
  static const _barCount = 28;

  Timer? _timer;
  StreamSubscription<Amplitude>? _ampSub;
  int _seconds = 0;
  final List<double> _levels = List.filled(_barCount, 0.0);

  /// True while stopping/cancelling — the buttons lock so a double tap
  /// can't race the recorder.
  bool _busy = false;

  bool get _reduceMotion => AppPreferences.instance.reduceMotion.value;

  void _haptic(Future<void> Function() feedback) {
    if (AppPreferences.instance.hapticsEnabled.value) feedback();
  }

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/voice-note-${DateTime.now().millisecondsSinceEpoch}.wav';
      await widget.recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );
      _ampSub = widget.recorder
          .onAmplitudeChanged(const Duration(milliseconds: 120))
          .listen(_onAmplitude);
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _seconds++);
        if (_seconds >= VoiceNotePill.maxSeconds) _send();
      });
    } catch (_) {
      // Recorder failed to start (e.g. mic in use elsewhere): bail out
      // cleanly instead of trapping the user in a dead pill.
      if (!mounted) return;
      toast(context, 'Could not start recording.');
      widget.onDiscard();
    }
  }

  void _onAmplitude(Amplitude amp) {
    if (!mounted || _busy) return;
    // dBFS, roughly -60 (silence) .. 0 (loud). Floor the bar so it never
    // fully vanishes mid-recording.
    final level = ((amp.current + 55) / 55).clamp(0.0, 1.0);
    setState(() {
      _levels.removeAt(0);
      _levels.add(0.15 + 0.85 * level);
    });
  }

  Future<void> _send() async {
    if (_busy) return;
    setState(() => _busy = true);
    _haptic(HapticFeedback.mediumImpact);
    _timer?.cancel();
    await _ampSub?.cancel();
    String? path;
    try {
      path = await widget.recorder.stop();
    } catch (_) {
      path = null;
    }
    if (!mounted) return;
    if (path == null || !File(path).existsSync()) {
      widget.onDiscard();
      return;
    }
    widget.onFinished(path);
  }

  Future<void> _discard() async {
    if (_busy) return;
    setState(() => _busy = true);
    _haptic(HapticFeedback.lightImpact);
    _timer?.cancel();
    await _ampSub?.cancel();
    try {
      await widget.recorder.cancel();
    } catch (_) {}
    if (!mounted) return;
    widget.onDiscard();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ampSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mm = _seconds ~/ 60;
    final ss = (_seconds % 60).toString().padLeft(2, '0');
    return Container(
      decoration: BoxDecoration(
        color: P.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: P.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: Row(
        children: [
          _pillButton(
              Icons.delete_outline_rounded, 'Discard recording', _discard),
          const SizedBox(width: 6),
          SizedBox(
            width: 46,
            child: Text(
              '$mm:$ss',
              style: PT.body.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 2),
          Expanded(child: _waveform()),
          const SizedBox(width: 8),
          _sendButton(),
        ],
      ),
    );
  }

  Widget _waveform() {
    return SizedBox(
      height: 36,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < _barCount; i++)
            _bar(_reduceMotion ? 0.35 : _levels[i], i),
        ],
      ),
    );
  }

  Widget _bar(double level, int index) {
    final h = 4.0 + level * 28.0;
    final recent = index >= _barCount - 6;
    return Container(
      width: 3,
      height: h,
      margin: const EdgeInsets.symmetric(horizontal: 1.5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(2),
        color: recent ? P.accent : P.inkFaint,
      ),
    );
  }

  Widget _pillButton(IconData icon, String tooltip, VoidCallback onTap) {
    return GestureDetector(
      onTap: _busy ? null : onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: P.tonal,
        ),
        alignment: Alignment.center,
        child: Icon(icon,
            size: 22, color: P.inkSecondary, weight: 1.6,
            semanticLabel: tooltip),
      ),
    );
  }

  Widget _sendButton() {
    return GestureDetector(
      onTap: _busy ? null : _send,
      child: AnimatedOpacity(
        duration: Duration(milliseconds: _reduceMotion ? 0 : 150),
        opacity: _busy ? 0.5 : 1,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: P.accent,
          ),
          alignment: Alignment.center,
          child: _busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.arrow_upward_rounded,
                  color: Colors.white, size: 22),
        ),
      ),
    );
  }
}
