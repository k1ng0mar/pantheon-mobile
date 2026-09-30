import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show sqrt;
import 'dart:typed_data';

/// WebSocket client for the live-voice protocol.
///
/// Backend: `GET /agui/voice/live` on the dashboard/agui serve surface
/// (see `pantheon-gateway/src/live_voice.rs`). Wire format is 16 kHz mono
/// 16-bit PCM both ways.
///
/// Client -> server:
/// - text `{"type":"start"}` begins an utterance
/// - binary frames carry PCM chunks
/// - text `{"type":"end"}` closes the utterance for transcription
/// - text `{"type":"stop"}` ends the session
///
/// Server -> client:
/// - `{"type":"ready"}` once the session is accepted
/// - `{"type":"transcript","text":...,"final":true}` (STT result)
/// - `{"type":"reply_text","text":...}` (agent reply as text, always sent)
/// - binary PCM chunks of the spoken reply
/// - `{"type":"audio_end"}` when the reply audio finishes
/// - `{"type":"busy"}` when audio arrives while a turn is in flight
///   (dropped by the server, never queued — no barge-in in v1)
/// - `{"type":"approval_needed","text":...}` when a tool approval parks
///   the turn. Approvals stay text-only and are never auto-approved.
/// - `{"type":"error","code":...}` machine-readable error code
/// - `{"type":"end"}` when the server closes the session
///
/// Auth uses the same token as the dashboard HTTP API, sent as the
/// `x-pantheon-token` handshake header (the agui layer also accepts
/// `Authorization: Bearer` and `?token=`, but a header keeps the token
/// out of URLs and logs).
class LiveVoiceClient {
  LiveVoiceClient({required this.baseUrl, required this.token});

  final String baseUrl;
  final String token;

  WebSocket? _ws;
  final _events = StreamController<LiveVoiceEvent>.broadcast();
  bool _closed = false;

  /// Parsed server -> client events.
  Stream<LiveVoiceEvent> get events => _events.stream;

  /// Open the WebSocket session. Completes when the TCP/WebSocket
  /// handshake succeeds; the server still sends `ready` (or `error`)
  /// as the first protocol event.
  Future<void> connect() async {
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final httpUri = Uri.parse('$base/agui/voice/live');
    final wsUri = httpUri.replace(
      scheme: httpUri.scheme == 'https' ? 'wss' : 'ws',
    );
    final ws = await WebSocket.connect(
      wsUri.toString(),
      headers: {'x-pantheon-token': token},
    );
    _ws = ws;
    ws.listen(
      _onMessage,
      onError: (Object e) {
        if (!_closed) {
          _events.add(LiveVoiceError('connection_error'));
        }
      },
      onDone: () {
        if (!_closed) _events.add(const LiveVoiceSessionEnd());
      },
      cancelOnError: false,
    );
  }

  void _onMessage(dynamic data) {
    if (data is String) {
      Map<String, dynamic>? msg;
      try {
        msg = jsonDecode(data) as Map<String, dynamic>;
      } catch (_) {
        return; // ignore malformed text frames
      }
      switch (msg['type']) {
        case 'ready':
          _events.add(const LiveVoiceReady());
        case 'transcript':
          _events.add(LiveVoiceTranscript(
            (msg['text'] ?? '').toString(),
            final_: msg['final'] == true,
          ));
        case 'reply_text':
          _events.add(LiveVoiceReplyText((msg['text'] ?? '').toString()));
        case 'audio_end':
          _events.add(const LiveVoiceAudioEnd());
        case 'busy':
          _events.add(const LiveVoiceBusy());
        case 'approval_needed':
          _events.add(LiveVoiceApprovalNeeded((msg['text'] ?? '').toString()));
        case 'error':
          _events.add(LiveVoiceError((msg['code'] ?? 'unknown').toString()));
        case 'end':
          _events.add(const LiveVoiceSessionEnd());
      }
    } else if (data is List<int>) {
      _events.add(LiveVoiceAudioChunk(Uint8List.fromList(data)));
    }
  }

  void _sendText(Map<String, String> msg) {
    _ws?.add(jsonEncode(msg));
  }

  /// Begin an utterance. Binary PCM frames sent after this are buffered
  /// by the server until [sendEnd].
  void sendStart() => _sendText({'type': 'start'});

  /// One chunk of 16 kHz mono 16-bit PCM audio.
  void sendPcm(Uint8List pcm) {
    if (pcm.isNotEmpty) _ws?.add(pcm);
  }

  /// Close the utterance; the server transcribes and runs the turn.
  void sendEnd() => _sendText({'type': 'end'});

  /// End the whole session (server replies with `end`).
  void sendStop() => _sendText({'type': 'stop'});

  Future<void> close() async {
    _closed = true;
    try {
      await _ws?.close();
    } catch (_) {}
    _ws = null;
    if (!_events.isClosed) await _events.close();
  }
}

/// Server -> client events of the live-voice protocol.
sealed class LiveVoiceEvent {
  const LiveVoiceEvent();
}

/// Session accepted; the client may now send utterances.
class LiveVoiceReady extends LiveVoiceEvent {
  const LiveVoiceReady();
}

/// STT result for the just-closed utterance.
class LiveVoiceTranscript extends LiveVoiceEvent {
  final String text;
  final bool final_;
  const LiveVoiceTranscript(this.text, {this.final_ = true});
}

/// The agent's reply as text. Always sent, even when TTS produced audio.
class LiveVoiceReplyText extends LiveVoiceEvent {
  final String text;
  const LiveVoiceReplyText(this.text);
}

/// One binary chunk of the spoken reply (16 kHz mono 16-bit PCM).
class LiveVoiceAudioChunk extends LiveVoiceEvent {
  final Uint8List pcm;
  const LiveVoiceAudioChunk(this.pcm);
}

/// The spoken reply finished; all its PCM chunks were delivered.
class LiveVoiceAudioEnd extends LiveVoiceEvent {
  const LiveVoiceAudioEnd();
}

/// Audio arrived while a turn was in flight; the server dropped it.
/// Not an error — the client should just keep listening.
class LiveVoiceBusy extends LiveVoiceEvent {
  const LiveVoiceBusy();
}

/// A tool approval parked the turn. Text-only: surface it, never
/// auto-approve. The user acts from the Approvals screen.
class LiveVoiceApprovalNeeded extends LiveVoiceEvent {
  final String scope;
  const LiveVoiceApprovalNeeded(this.scope);
}

/// Machine-readable failure (`live_disabled`, `voice_not_configured`,
/// `voice_backend_misconfigured`, `turn_rejected`, `turn_timeout`, ...).
class LiveVoiceError extends LiveVoiceEvent {
  final String code;
  const LiveVoiceError(this.code);
}

/// The server closed the session (or the socket dropped).
class LiveVoiceSessionEnd extends LiveVoiceEvent {
  const LiveVoiceSessionEnd();
}

/// 16 kHz mono 16-bit PCM helpers, mirroring
/// `pantheon-gateway/src/live_voice.rs`.
class Pcm16 {
  Pcm16._();

  static const sampleRate = 16000;

  /// RMS energy of 16-bit little-endian PCM samples (0.0 for empty).
  /// The server's speech threshold is 400.0: quiet-room noise sits well
  /// under 100, normal speech clears 1000 easily.
  static double rms(Uint8List pcm) {
    if (pcm.length < 2) return 0.0;
    final samples = pcm.length ~/ 2;
    var sum = 0.0;
    final bytes = ByteData.sublistView(pcm);
    for (var i = 0; i < samples; i++) {
      final s = bytes.getInt16(i * 2, Endian.little).toDouble();
      sum += s * s;
    }
    return sqrt(sum / samples);
  }

  /// Wrap raw 16 kHz mono 16-bit PCM in a 44-byte WAV header so players
  /// that need a container can play it. Mirrors the server's `wav_wrap`.
  static Uint8List wavWrap(Uint8List pcm) {
    final dataLen = pcm.length;
    final out = BytesBuilder();
    final h = ByteData(44);
    h.setUint32(0, 0x52494646, Endian.big); // "RIFF"
    h.setUint32(4, 36 + dataLen, Endian.little);
    h.setUint32(8, 0x57415645, Endian.big); // "WAVE"
    h.setUint32(12, 0x666d7420, Endian.big); // "fmt "
    h.setUint32(16, 16, Endian.little); // fmt chunk size
    h.setUint16(20, 1, Endian.little); // PCM
    h.setUint16(22, 1, Endian.little); // mono
    h.setUint32(24, sampleRate, Endian.little);
    h.setUint32(28, sampleRate * 2, Endian.little); // byte rate
    h.setUint16(32, 2, Endian.little); // block align
    h.setUint16(34, 16, Endian.little); // bits per sample
    h.setUint32(36, 0x64617461, Endian.big); // "data"
    h.setUint32(40, dataLen, Endian.little);
    out.add(h.buffer.asUint8List());
    out.add(pcm);
    return out.toBytes();
  }
}
