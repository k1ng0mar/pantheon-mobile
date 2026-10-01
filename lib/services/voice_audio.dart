import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:record/record.dart';

/// Microphone + speaker for live voice mode.
///
/// DEPENDENCIES (in pubspec.yaml — run `flutter pub get` after edits):
/// - `record: ^5.1.2` — mic capture as 16 kHz mono 16-bit PCM
/// - `audioplayers: ^6.1.0` — playback of the agent's spoken replies
///
/// Both are wrapped in thin classes so the voice screen never touches
/// plugin APIs directly; swapping providers later means editing this
/// file only.
///
/// Platform setup also required:
/// - Android: `RECORD_AUDIO` in AndroidManifest.xml
/// - iOS: `NSMicrophoneUsageDescription` in Info.plist

/// Live microphone streaming 16 kHz mono 16-bit PCM chunks.
///
/// The `record` plugin's `startStream` yields raw PCM frames of varying
/// size; this class re-chunks them to [frameBytes] so the protocol layer
/// always sends tidy ~100 ms frames and the level meter sees uniform
/// windows.
class VoiceMic {
  VoiceMic({this.frameBytes = 3200});

  /// Bytes per emitted frame: 3200 = 100 ms at 16 kHz 16-bit mono.
  /// Matches the server's `CHUNK_BYTES` and stays far under its
  /// 64 KiB per-frame cap.
  final int frameBytes;

  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _sub;
  final _chunks = StreamController<Uint8List>.broadcast();
  final _pending = BytesBuilder();

  /// PCM chunk stream. Starts the mic; throws [VoiceMicException] when
  /// permission is denied or the recorder fails to start.
  Future<Stream<Uint8List>> start() async {
    if (!await _recorder.hasPermission()) {
      throw VoiceMicException('Microphone permission denied.');
    }
    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );
    _sub = stream.listen(
      _onData,
      onError: (Object e) => _chunks.addError(e),
      cancelOnError: false,
    );
    return _chunks.stream;
  }

  void _onData(Uint8List data) {
    _pending.add(data);
    var buffered = _pending.toBytes();
    while (buffered.length >= frameBytes) {
      _chunks.add(buffered.sublist(0, frameBytes));
      buffered = buffered.sublist(frameBytes);
    }
    _pending.clear();
    _pending.add(buffered);
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    try {
      await _recorder.stop();
    } catch (_) {}
    _pending.clear();
  }

  Future<void> dispose() async {
    await stop();
    await _chunks.close();
    _recorder.dispose();
  }
}

class VoiceMicException implements Exception {
  final String message;
  VoiceMicException(this.message);
  @override
  String toString() => message;
}

/// Plays the agent's spoken replies.
///
/// The protocol delivers reply audio as binary PCM chunks followed by
/// `audio_end`; this class accumulates them and plays the utterance as
/// one WAV once it is complete. Trade-off vs true streaming: playback
/// starts after the full reply audio arrives instead of chunk-by-chunk,
/// but it needs no custom audio pipeline and can't underrun.
class VoiceSpeaker {
  final AudioPlayer _player = AudioPlayer();
  final _done = StreamController<void>.broadcast();

  /// Fires when the current utterance finishes playing (or is stopped).
  Stream<void> get onDone => _done.stream;

  VoiceSpeaker() {
    _player.onPlayerComplete.listen((_) {
      if (!_done.isClosed) _done.add(null);
    });
  }

  /// Play WAV bytes (see `Pcm16.wavWrap`). Stops any in-flight playback
  /// first.
  Future<void> playWav(Uint8List wav) async {
    await _player.stop();
    await _player.play(BytesSource(wav));
  }

  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {}
    if (!_done.isClosed) _done.add(null);
  }

  Future<void> dispose() async {
    await _player.dispose();
    await _done.close();
  }
}
