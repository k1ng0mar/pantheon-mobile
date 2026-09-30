import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/live_voice_client.dart';
import '../services/pantheon_api.dart';
import '../services/voice_audio.dart';
import '../theme.dart';

/// Opt-in live voice mode. NOT the default chat path.
///
/// Streams microphone audio as 16 kHz mono 16-bit PCM over the
/// `GET /agui/voice/live` WebSocket, shows the rolling transcript, and
/// plays the agent's spoken replies. The server runs one agent turn per
/// utterance on its own thread, so this screen takes no run id.
///
/// Turn-taking is client-driven with energy VAD: while the mic is live,
/// speech above the server's 400.0 RMS threshold opens an utterance
/// (`start`), and ~800 ms of silence closes it (`end`) for transcription.
/// The server also auto-closes as a safety net.
///
/// Approvals stay text-only: an `approval_needed` event renders as a
/// card and is never auto-approved — the user decides from Approvals.
class VoiceScreen extends StatefulWidget {
  const VoiceScreen({super.key, required this.api});

  final PantheonApi api;

  @override
  State<VoiceScreen> createState() => _VoiceScreenState();
}

enum _Status {
  connecting,
  listening,
  thinking,
  speaking,
  error,
  ended,
}

class _VoiceMsg {
  final bool user;
  final String text;
  final bool approval;
  _VoiceMsg({required this.user, required this.text, this.approval = false});
}

class _VoiceScreenState extends State<VoiceScreen> with WidgetsBindingObserver {
  LiveVoiceClient? _client;
  VoiceMic? _mic;
  final _speaker = VoiceSpeaker();

  StreamSubscription<LiveVoiceEvent>? _eventsSub;
  StreamSubscription<Uint8List>? _micSub;
  StreamSubscription<void>? _speakerDoneSub;
  Timer? _vadTimer;

  _Status _status = _Status.connecting;
  String? _statusNote;
  final _messages = <_VoiceMsg>[];
  double _level = 0.0;

  bool _listening = false; // mic toggle
  bool _utteranceOpen = false;
  DateTime? _lastSpeech;
  bool _ready = false;
  bool _busyFlash = false;
  bool _backgrounded = false; // torn down because the app backgrounded
  final _replyPcm = BytesBuilder();
  final _scroll = ScrollController();
  String? _fatalError;

  static const _speechThreshold = 400.0; // server SPEECH_RMS_THRESHOLD
  static const _silenceClose = Duration(milliseconds: 800);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _boot();
  }

  Future<void> _boot() async {
    final client = LiveVoiceClient(
      baseUrl: widget.api.baseUrl,
      token: widget.api.token,
    );
    _client = client;
    _eventsSub = client.events.listen(_onEvent);
    try {
      await client.connect();
    } catch (e) {
      _fail('connection_error');
      return;
    }
    // If the server refuses (gate failure), it sends `error` then `end`
    // before `ready`; _onEvent handles it.
  }

  Future<void> _startMic() async {
    if (_mic != null) return;
    final mic = VoiceMic();
    late final Stream<Uint8List> stream;
    try {
      stream = await mic.start();
    } catch (e) {
      _addSystem(e.toString());
      setState(() => _listening = false);
      return;
    }
    _mic = mic;
    _micSub = stream.listen(_onMicChunk, onError: (Object e) {
      _addSystem('Microphone error: $e');
      _setListening(false);
    });
    _vadTimer ??= Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => _vadTick(),
    );
  }

  Future<void> _stopMic() async {
    if (_utteranceOpen) _closeUtterance();
    await _micSub?.cancel();
    _micSub = null;
    await _mic?.dispose();
    _mic = null;
    _vadTimer?.cancel();
    _vadTimer = null;
    setState(() => _level = 0.0);
  }

  Future<void> _setListening(bool on) async {
    if (!mounted || _status == _Status.ended) return;
    setState(() => _listening = on);
    if (on) {
      await _startMic();
    } else {
      await _stopMic();
    }
    _updateStatus();
  }

  void _onMicChunk(Uint8List chunk) {
    if (!mounted || !_listening) return;
    final rms = Pcm16.rms(chunk);
    // Perceptual-ish curve for the meter: speech (~1000+) reads high,
    // room noise (<100) barely moves it.
    final level = (rms / 2000).clamp(0.0, 1.0);
    setState(() => _level = level * level * (3 - 2 * level)); // smoothstep
    if (rms >= _speechThreshold) {
      _lastSpeech = DateTime.now();
      if (!_utteranceOpen && _ready) {
        _utteranceOpen = true;
        _client?.sendStart();
      }
    }
    if (_utteranceOpen) _client?.sendPcm(chunk);
  }

  void _vadTick() {
    if (!_utteranceOpen || !_listening) return;
    final last = _lastSpeech;
    if (last != null &&
        DateTime.now().difference(last) >= _silenceClose) {
      _closeUtterance();
    }
  }

  void _closeUtterance() {
    if (!_utteranceOpen) return;
    _utteranceOpen = false;
    _lastSpeech = null;
    _client?.sendEnd();
    _updateStatus(note: null);
    setState(() => _status = _Status.thinking);
  }

  void _onEvent(LiveVoiceEvent event) {
    if (!mounted) return;
    switch (event) {
      case LiveVoiceReady():
        _ready = true;
        _setListening(true);
      case LiveVoiceTranscript(:final text):
        if (text.trim().isNotEmpty) {
          setState(() {
            _messages.add(_VoiceMsg(user: true, text: text.trim()));
            _status = _Status.thinking;
            _statusNote = null;
          });
          _scrollToEnd();
        }
      case LiveVoiceReplyText(:final text):
        if (text.trim().isNotEmpty) {
          setState(() => _messages.add(_VoiceMsg(user: false, text: text)));
          _scrollToEnd();
        }
      case LiveVoiceAudioChunk(:final pcm):
        _replyPcm.add(pcm);
      case LiveVoiceAudioEnd():
        _playReply();
      case LiveVoiceBusy():
        setState(() {
          _busyFlash = true;
          _statusNote = 'Finishing the last reply — hold that thought.';
        });
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _busyFlash = false);
        });
      case LiveVoiceApprovalNeeded(:final scope):
        // Text-only, never auto-approved.
        setState(() {
          _messages.add(_VoiceMsg(
            user: false,
            text: scope.isEmpty ? 'Approval requested.' : scope,
            approval: true,
          ));
          _updateStatus();
        });
        _scrollToEnd();
      case LiveVoiceError(:final code):
        _fail(code);
      case LiveVoiceSessionEnd():
        if (_status != _Status.error) {
          setState(() => _status = _Status.ended);
          _teardown();
        }
    }
  }

  Future<void> _playReply() async {
    final pcm = _replyPcm.toBytes();
    _replyPcm.clear();
    if (pcm.isEmpty) {
      _updateStatus();
      return;
    }
    setState(() => _status = _Status.speaking);
    await _speakerDoneSub?.cancel();
    _speakerDoneSub = _speaker.onDone.listen((_) {
      if (mounted) _updateStatus();
    });
    try {
      await _speaker.playWav(Pcm16.wavWrap(pcm));
    } catch (_) {
      // Playback is best-effort; the reply text is already on screen.
      _updateStatus();
    }
  }

  void _updateStatus({String? note}) {
    if (!mounted || _status == _Status.error || _status == _Status.ended) {
      return;
    }
    setState(() {
      _statusNote = note;
      if (_utteranceOpen) {
        _status = _Status.listening;
      } else if (_listening) {
        _status = _Status.listening;
      }
    });
  }

  void _addSystem(String text) {
    setState(() => _messages.add(_VoiceMsg(user: false, text: text)));
    _scrollToEnd();
  }

  void _fail(String code) {
    setState(() {
      _status = _Status.error;
      _fatalError = _friendlyError(code);
    });
    _teardown();
  }

  String _friendlyError(String code) {
    switch (code) {
      case 'live_disabled':
        return 'Live voice is switched off on the server ([voice] live_enabled).';
      case 'voice_not_configured':
        return 'Voice is not configured on the server — it needs [tools] voice plus [stt] and [tts].';
      case 'voice_backend_misconfigured':
        return 'A voice backend on the server is misconfigured. Check the server config.';
      case 'turn_rejected':
        return 'The server rejected the turn.';
      case 'turn_timeout':
        return 'The turn took too long and timed out.';
      case 'connection_error':
        return 'Could not reach the voice session. Is the dashboard reachable?';
      default:
        return 'Voice error: $code';
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _endCall() async {
    setState(() => _status = _Status.ended);
    try {
      _client?.sendStop();
    } catch (_) {}
    await _teardown();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _teardown() async {
    _vadTimer?.cancel();
    _vadTimer = null;
    await _micSub?.cancel();
    _micSub = null;
    await _eventsSub?.cancel();
    _eventsSub = null;
    await _speakerDoneSub?.cancel();
    _speakerDoneSub = null;
    await _mic?.dispose();
    _mic = null;
    await _speaker.stop();
    try {
      await _client?.close();
    } catch (_) {}
    _client = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _teardown();
    _speaker.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _suspendForBackground();
    } else if (state == AppLifecycleState.resumed && _backgrounded) {
      // The session is already torn down to a clean idle state with a
      // notice on screen. Never silently resume a stale socket — the
      // user starts a fresh session explicitly.
      _backgrounded = false;
      if (mounted) setState(() {});
    }
  }

  /// Tear the session down when the app backgrounds: the mic must never
  /// stay hot and the socket must not linger while the phone is locked.
  Future<void> _suspendForBackground() async {
    if (_backgrounded ||
        _status == _Status.ended ||
        _status == _Status.error) {
      return;
    }
    _backgrounded = true;
    try {
      _client?.sendStop();
    } catch (_) {}
    await _stopMic();
    await _speaker.stop();
    await _eventsSub?.cancel();
    _eventsSub = null;
    try {
      await _client?.close();
    } catch (_) {}
    _client = null;
    if (!mounted) return;
    setState(() {
      _status = _Status.ended;
      _ready = false;
      _listening = false;
      _utteranceOpen = false;
      _level = 0.0;
    });
    _addSystem(
        'Session paused — the app went to the background, so the microphone was switched off and the connection closed. Tap "New session" to start again.');
  }

  Future<void> _reconnect() async {
    if (_status == _Status.connecting) return;
    setState(() {
      _backgrounded = false;
      _status = _Status.connecting;
      _statusNote = null;
      _fatalError = null;
    });
    await _boot();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.chevron_left_rounded,
              size: 30, color: P.ink, weight: 1.6),
          onPressed: _endCall,
        ),
        title: const Text('Live voice'),
        centerTitle: false,
      ),
      body: SafeArea(
        child: Column(
          children: [
            _statusHeader(),
            _levelMeter(),
            Expanded(child: _transcript()),
            _controls(),
          ],
        ),
      ),
    );
  }

  Widget _statusHeader() {
    final (label, color) = switch (_status) {
      _Status.connecting => ('Connecting…', P.inkMuted),
      _Status.listening => !_listening
          ? ('Paused', P.inkFaint)
          : _utteranceOpen
              ? ('Listening…', P.live)
              : ('Listening', P.inkMuted),
      _Status.thinking => ('Thinking…', P.info),
      _Status.speaking => ('Speaking', P.ok),
      _Status.error => ('Error', P.err),
      _Status.ended =>
        _backgrounded ? ('Paused', P.warn) : ('Ended', P.inkFaint),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
            ),
          ),
          const SizedBox(width: 10),
          Text(label, style: PT.label.copyWith(color: color)),
          if (_busyFlash && _statusNote != null) ...[
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _statusNote!,
                style: PT.small.copyWith(color: P.warn),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _levelMeter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(P.r8),
        child: Container(
          height: 10,
          color: P.tonal,
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: _level.clamp(0.0, 1.0),
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF7223FF), Color(0xFF8B5CFF)],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _transcript() {
    if (_fatalError != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.mic_off_outlined, size: 48, color: P.err),
            const SizedBox(height: 16),
            Text(_fatalError!, style: PT.body, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Back'),
            ),
          ],
        ),
      );
    }
    if (_messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            _status == _Status.connecting
                ? 'Opening the voice session…'
                : 'Speak and the agent will answer in voice.\nTap the mic to pause listening.',
            style: PT.body.copyWith(color: P.inkMuted),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: _messages.length,
      itemBuilder: (context, i) => _bubble(_messages[i]),
    );
  }

  Widget _bubble(_VoiceMsg msg) {
    if (msg.approval) {
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: P.warn.withValues(alpha: 0.08),
          border: Border.all(color: P.warn.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(P.r12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lock_outline_rounded, size: 16, color: P.warn),
                const SizedBox(width: 6),
                Text('Approval needed',
                    style: PT.label.copyWith(color: P.warn)),
              ],
            ),
            const SizedBox(height: 8),
            Text(msg.text, style: PT.body),
            const SizedBox(height: 8),
            Text(
              'Voice never auto-approves. Decide from the Approvals tab.',
              style: PT.small.copyWith(color: P.inkMuted),
            ),
          ],
        ),
      );
    }
    final align =
        msg.user ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final bg = msg.user ? P.accentSoft : P.surface;
    final border =
        msg.user ? Border.all(color: P.accent.withValues(alpha: 0.35)) : Border.all(color: P.border);
    return Column(
      crossAxisAlignment: align,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            border: border,
            borderRadius: BorderRadius.circular(P.r14),
          ),
          child: Text(msg.text, style: PT.body),
        ),
      ],
    );
  }

  Widget _controls() {
    if (_backgrounded) {
      return Container(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: P.divider)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _roundButton(
              icon: Icons.refresh_rounded,
              label: 'New session',
              background: P.accent,
              foreground: Colors.white,
              onPressed: _reconnect,
            ),
            _roundButton(
              icon: Icons.call_end_rounded,
              label: 'Close',
              background: P.tonal,
              foreground: P.inkMuted,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: P.divider)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _roundButton(
            icon: _listening
                ? Icons.mic_rounded
                : Icons.mic_off_rounded,
            label: _listening ? 'Mute' : 'Unmute',
            background: _listening ? P.accent : P.tonal,
            foreground: _listening ? Colors.white : P.inkMuted,
            onPressed: _ready && _fatalError == null
                ? () => _setListening(!_listening)
                : null,
          ),
          _roundButton(
            icon: Icons.call_end_rounded,
            label: 'End',
            background: P.err,
            foreground: Colors.white,
            onPressed: _endCall,
          ),
        ],
      ),
    );
  }

  Widget _roundButton({
    required IconData icon,
    required String label,
    required Color background,
    required Color foreground,
    required VoidCallback? onPressed,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Opacity(
          opacity: onPressed == null ? 0.4 : 1.0,
          child: Material(
            color: background,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPressed,
              child: SizedBox(
                width: 64,
                height: 64,
                child: Icon(icon, color: foreground, size: 28),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: PT.small.copyWith(color: P.inkMuted)),
      ],
    );
  }
}
