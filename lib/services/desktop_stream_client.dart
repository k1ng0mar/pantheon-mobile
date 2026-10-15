import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// WebSocket client for the Bot Screen desktop stream.
///
/// Backend: `GET /api/desktop/stream?fps=<1-10>` on the dashboard serve
/// surface (see `pantheon-dashboard/src/desktop.rs`). The server opens with
/// one `{"type":"ready",...}` text frame, then pushes binary frames (one
/// screenshot per frame, PNG bytes) at up to the requested fps. Later text
/// frames carry `{"type":"error",...}`; they surface on [state] and the
/// stream keeps going.
///
/// Auth uses the same token as the dashboard HTTP API, sent as the
/// `x-pantheon-token` handshake header — the same convention as
/// [BrowserStreamClient], keeping the token out of URLs and logs.
enum DesktopStreamState { connecting, live, error, closed }

class DesktopStreamClient {
  DesktopStreamClient({
    required this.baseUrl,
    required this.token,
    required this.fps,
  });

  final String baseUrl;
  final String token;
  final int fps;

  WebSocket? _ws;
  final _frames = StreamController<Uint8List>.broadcast();
  final _state = StreamController<DesktopStreamState>.broadcast();
  bool _closed = false;

  /// Latest screenshot bytes, one event per frame.
  Stream<Uint8List> get frames => _frames.stream;

  /// Connection lifecycle: connecting, then live, error, or closed.
  Stream<DesktopStreamState> get state => _state.stream;

  /// Open the stream. Completes when the WebSocket handshake succeeds;
  /// frames arrive on [frames] afterwards.
  Future<void> connect() async {
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final httpUri = Uri.parse('$base/api/desktop/stream').replace(
      queryParameters: {'fps': fps.clamp(1, 10).toString()},
    );
    final wsUri = httpUri.replace(
      scheme: httpUri.scheme == 'https' ? 'wss' : 'ws',
    );
    _state.add(DesktopStreamState.connecting);
    WebSocket ws;
    try {
      ws = await WebSocket.connect(
        wsUri.toString(),
        headers: {'x-pantheon-token': token},
      );
    } catch (e) {
      if (!_closed) _state.add(DesktopStreamState.error);
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
    _state.add(DesktopStreamState.live);
    ws.listen(
      (dynamic data) {
        if (_closed) return;
        if (data is List<int> && data.isNotEmpty) {
          _frames.add(Uint8List.fromList(data));
        }
        // Text frames are control traffic (ready/error); nothing to
        // decode for the viewer, and ignoring them keeps error text
        // from ever being mistaken for a frame.
      },
      onError: (_) {
        if (!_closed) _state.add(DesktopStreamState.error);
      },
      onDone: () {
        if (!_closed) _state.add(DesktopStreamState.closed);
      },
      cancelOnError: false,
    );
  }

  /// Close the stream and release resources. Safe to call twice.
  Future<void> dispose() async {
    _closed = true;
    try {
      await _ws?.close();
    } catch (_) {}
    _ws = null;
    if (!_frames.isClosed) await _frames.close();
    if (!_state.isClosed) await _state.close();
  }
}
