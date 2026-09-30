import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// WebSocket client for the browser screenshot stream.
///
/// Backend: `GET /api/browser/stream?session=<name>&fps=<1-10>` on the
/// dashboard serve surface (see `pantheon-dashboard/src/browser.rs`).
/// The server pushes binary frames (one screenshot per frame, PNG/JPEG
/// bytes) at up to the requested fps; text frames, if any, are ignored.
///
/// Auth uses the same token as the dashboard HTTP API, sent as the
/// `x-pantheon-token` handshake header — the same convention as
/// [LiveVoiceClient], keeping the token out of URLs and logs.
class BrowserStreamClient {
  BrowserStreamClient({
    required this.baseUrl,
    required this.token,
    required this.session,
    required this.fps,
  });

  final String baseUrl;
  final String token;
  final String session;
  final int fps;

  WebSocket? _ws;
  final _frames = StreamController<Uint8List>.broadcast();
  final _state = StreamController<BrowserStreamState>.broadcast();
  bool _closed = false;

  /// Latest screenshot bytes, one event per frame.
  Stream<Uint8List> get frames => _frames.stream;

  /// Connection lifecycle: connected, then disconnected or error.
  Stream<BrowserStreamState> get state => _state.stream;

  /// Open the stream. Completes when the WebSocket handshake succeeds;
  /// frames arrive on [frames] afterwards.
  Future<void> connect() async {
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final httpUri = Uri.parse('$base/api/browser/stream').replace(
      queryParameters: {
        'session': session,
        'fps': fps.clamp(1, 10).toString(),
      },
    );
    final wsUri = httpUri.replace(
      scheme: httpUri.scheme == 'https' ? 'wss' : 'ws',
    );
    _state.add(BrowserStreamState.connecting);
    WebSocket ws;
    try {
      ws = await WebSocket.connect(
        wsUri.toString(),
        headers: {'x-pantheon-token': token},
      );
    } catch (e) {
      if (!_closed) _state.add(BrowserStreamState.error);
      rethrow;
    }
    if (_closed) {
      // Disposed while the handshake was in flight: don't leak it.
      try {
        await ws.close();
      } catch (_) {}
      return;
    }
    _ws = ws;
    _state.add(BrowserStreamState.live);
    ws.listen(
      (dynamic data) {
        if (data is List<int> && data.isNotEmpty && !_closed) {
          _frames.add(Uint8List.fromList(data));
        }
        // Text frames carry no screenshot payload; ignore them.
      },
      onError: (Object e) {
        if (!_closed) _state.add(BrowserStreamState.error);
      },
      onDone: () {
        if (!_closed) _state.add(BrowserStreamState.disconnected);
      },
      cancelOnError: false,
    );
  }

  Future<void> close() async {
    _closed = true;
    try {
      await _ws?.close();
    } catch (_) {}
    _ws = null;
    if (!_frames.isClosed) await _frames.close();
    if (!_state.isClosed) await _state.close();
  }
}

enum BrowserStreamState { connecting, live, disconnected, error }
