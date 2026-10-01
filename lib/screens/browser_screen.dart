import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/browser_stream_client.dart';
import '../services/pantheon_api.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/forms.dart';
import '../widgets/pantheon_card.dart';
import '../widgets/states.dart';

/// Browser: live screenshot stream of the agent's browser session with
/// take-control input (tap / type / scroll / navigate).
///
/// Backend: `GET /api/browser/status`, `GET /api/browser/stream` (WS),
/// `POST /api/browser/input` (see `pantheon-dashboard/src/browser.rs`).
class BrowserScreen extends StatefulWidget {
  final PantheonApi api;

  const BrowserScreen({super.key, required this.api});

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  Future<BrowserStatus>? _statusFuture;

  final _sessionCtrl = TextEditingController(text: 'default');
  final _typeCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  double _fps = 3;

  BrowserStreamClient? _client;
  StreamSubscription<Uint8List>? _frameSub;
  StreamSubscription<BrowserStreamState>? _stateSub;

  Uint8List? _frame;
  int? _imgW;
  int? _imgH;
  bool _decoding = false;

  /// Null = not connected yet; otherwise the last stream lifecycle state.
  BrowserStreamState? _streamState;
  String? _streamError;
  bool _sending = false;

  /// True once a live session's stream has ended (error or disconnect).
  /// Drives the "Completed · <session>" panel: the browser session may
  /// still be open server-side (there is no server-side stop endpoint —
  /// only GET status, GET stream, POST input), so this panel offers
  /// take-control or a plain disconnect of the local stream.
  bool _sessionEnded = false;

  /// Latest browser narration for this session, polled every 2s.
  /// Independent of `_statusFuture` so the card never flashes on poll.
  BrowserActivity? _activity;
  Timer? _activityPoll;

  @override
  void initState() {
    super.initState();
    _reloadStatus();
    _activityPoll = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _pollActivity(),
    );
    _pollActivity();
  }

  void _reloadStatus() {
    _disconnect();
    setState(() {
      _statusFuture = widget.api.browserStatus();
    });
  }

  /// Fetch the session's latest browser narration. Quiet: failures
  /// leave the last subtitle in place.
  Future<void> _pollActivity() async {
    if (!mounted) return;
    try {
      final status = await widget.api.browserStatus(session: _session);
      if (!mounted) return;
      setState(() => _activity = status.lastActivity);
    } catch (_) {}
  }

  /// Human subtitle for the latest browser activity. Null when there is
  /// nothing fresh to narrate: nothing recorded yet, or the action is
  /// stale (older than ~20s, so it has finished and the subtitle
  /// clears instead of lying).
  String? get _narration {
    final a = _activity;
    if (a == null || a.action.isEmpty) return null;
    if (a.at != null && DateTime.now().difference(a.at!).inSeconds > 20) {
      return null;
    }
    final d = a.detail;
    switch (a.action) {
      case 'tap':
        return 'Tapping…';
      case 'type':
      case 'fill-ref':
        return 'Typing…';
      case 'scroll':
        return 'Scrolling…';
      case 'navigate':
        return 'Opening ${d.isEmpty ? 'page' : d}…';
      case 'press':
        return 'Pressing ${d.isEmpty ? 'key' : d}…';
      case 'snapshot':
        return 'Reading the page…';
      case 'click':
      case 'click-ref':
        return 'Clicking…';
      case 'hover-ref':
        return 'Hovering…';
      case 'back':
        return 'Going back…';
      case 'forward':
        return 'Going forward…';
      case 'reload':
        return 'Reloading…';
      case 'wait-for':
        return 'Waiting…';
      case 'extract':
        return 'Extracting…';
      case 'act':
        return 'Acting…';
      case 'screenshot':
        return 'Capturing…';
      default:
        return '${a.action[0].toUpperCase()}${a.action.substring(1)}…';
    }
  }

  @override
  void dispose() {
    // Tear down the stream without setState: the widget is going away.
    _activityPoll?.cancel();
    _frameSub?.cancel();
    _stateSub?.cancel();
    _client?.close();
    _sessionCtrl.dispose();
    _typeCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _disconnect() async {
    await _frameSub?.cancel();
    await _stateSub?.cancel();
    _frameSub = null;
    _stateSub = null;
    final client = _client;
    _client = null;
    if (client != null) await client.close();
    if (mounted) {
      setState(() {
        _streamState = null;
        _streamError = null;
        _sessionEnded = false;
        _frame = null;
        _imgW = null;
        _imgH = null;
      });
    }
  }

  Future<void> _connect() async {
    await _disconnect();
    final session = _sessionCtrl.text.trim().isEmpty
        ? 'default'
        : _sessionCtrl.text.trim();
    final client = BrowserStreamClient(
      baseUrl: widget.api.baseUrl,
      token: widget.api.token,
      session: session,
      fps: _fps.round(),
    );
    _client = client;
    _frameSub = client.frames.listen(_onFrame);
    _stateSub = client.state.listen((s) {
      if (!mounted) return;
      setState(() {
        // A stream that was live and then ended leaves the session-end
        // panel: the browser session may still be open server-side, so
        // the user can take control of it or just disconnect this view
        // (no server-side stop endpoint exists).
        if ((s == BrowserStreamState.error ||
                s == BrowserStreamState.disconnected) &&
            _streamState == BrowserStreamState.live) {
          _sessionEnded = true;
        }
        _streamState = s;
        if (s == BrowserStreamState.error) {
          _streamError = 'The stream dropped unexpectedly.';
        }
      });
    });
    try {
      await client.connect();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _streamState = BrowserStreamState.error;
        _streamError = 'Could not open the stream ($e).';
      });
    }
  }

  void _onFrame(Uint8List bytes) {
    if (!mounted) return;
    setState(() => _frame = bytes);
    // Resolve the screenshot dimensions once (viewports rarely change
    // mid-session); skip while a decode is already in flight.
    if ((_imgW == null || _imgH == null) && !_decoding) {
      _decoding = true;
      decodeImageFromList(bytes).then((img) {
        _decoding = false;
        if (!mounted) return;
        if (_imgW != img.width || _imgH != img.height) {
          setState(() {
            _imgW = img.width;
            _imgH = img.height;
          });
        }
        img.dispose();
      }).catchError((_) {
        _decoding = false;
      });
    }
  }

  String get _session => _sessionCtrl.text.trim().isEmpty
      ? 'default'
      : _sessionCtrl.text.trim();

  Future<void> _sendInput(Map<String, dynamic> body) async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      await widget.api.browserInput({'session': _session, ...body});
    } catch (e) {
      if (mounted) toastError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _onTapImage(TapDownDetails d, BoxConstraints box) {
    if (_streamState != BrowserStreamState.live) return;
    final w = _imgW;
    final h = _imgH;
    if (w == null || h == null || w <= 0 || h <= 0) return;
    // The image fills the AspectRatio box exactly, so fractions map
    // linearly onto screenshot pixels.
    final fx = (d.localPosition.dx / box.maxWidth).clamp(0.0, 1.0);
    final fy = (d.localPosition.dy / box.maxHeight).clamp(0.0, 1.0);
    _sendInput({
      'action': 'tap',
      'x': fx * w,
      'y': fy * h,
    });
  }

  void _sendType() {
    final text = _typeCtrl.text;
    if (text.isEmpty) return;
    _typeCtrl.clear();
    _sendInput({'action': 'type', 'text': text});
  }

  void _navigate() {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) return;
    _sendInput({'action': 'navigate', 'url': url});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Browser'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded,
                color: P.inkSecondary, weight: 1.6),
            onPressed: _reloadStatus,
          ),
        ],
      ),
      body: FutureBuilder<BrowserStatus>(
        future: _statusFuture,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(
                child: CircularProgressIndicator(color: P.accent));
          }
          if (snap.hasError) {
            return EmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'Could not reach the browser backend',
              body: 'Check the dashboard connection and try again.',
              ctaLabel: 'Retry',
              onCta: _reloadStatus,
            );
          }
          final status = snap.data!;
          if (!status.enabled) {
            return EmptyState(
              icon: Icons.web_asset_off_outlined,
              title: 'Browser tool is off',
              body: 'Enable the browser tool (Tools screen) and '
                  'configure a backend to stream its session here.',
              ctaLabel: 'Reload',
              onCta: _reloadStatus,
            );
          }
          return _buildSession(context, status);
        },
      ),
    );
  }

  Widget _buildSession(BuildContext context, BrowserStatus status) {
    final live = _streamState == BrowserStreamState.live;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        PCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _LiveDot(live: live),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      live ? 'Live · ${_session}' : 'Session',
                      style: PT.cardTitle.copyWith(fontSize: 15),
                    ),
                  ),
                  Text(status.backend, style: PT.mono),
                ],
              ),
              if (_narration != null) ...[
                const SizedBox(height: 2),
                Text(
                  _narration!,
                  style: PT.meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (!live) ...[
                const SizedBox(height: 14),
                Text('Session name', style: PT.meta),
                const SizedBox(height: 6),
                TextField(
                  controller: _sessionCtrl,
                  style: PT.body,
                  decoration: _fieldDecoration('default'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text('Frame rate', style: PT.meta),
                    const Spacer(),
                    Text('${_fps.round()} fps', style: PT.label),
                  ],
                ),
                Slider(
                  value: _fps,
                  min: 1,
                  max: 10,
                  divisions: 9,
                  activeColor: P.accent,
                  inactiveColor: P.tonal,
                  label: '${_fps.round()} fps',
                  onChanged: (v) => setState(() => _fps = v),
                ),
                const SizedBox(height: 8),
                GradientButton(
                  label: _streamState == BrowserStreamState.connecting
                      ? 'Connecting…'
                      : 'Connect',
                  icon: Icons.play_arrow_rounded,
                  onTap: _streamState == BrowserStreamState.connecting
                      ? null
                      : _connect,
                ),
              ] else ...[
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: TonalButton(
                      label: 'Disconnect', onTap: _disconnect),
                ),
              ],
            ],
          ),
        ),
        if (_sessionEnded) ...[
          const SizedBox(height: 12),
          PCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.check_circle_rounded,
                        color: P.ok, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Completed · $_session',
                        style:
                            PT.cardTitle.copyWith(fontSize: 15),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'The stream ended, but the browser session may '
                  'still be open server-side. Take control to keep '
                  'watching it, or disconnect — disconnecting only '
                  'closes this view, not the session.',
                  style: PT.small
                      .copyWith(color: P.inkSecondary),
                ),
                const SizedBox(height: 12),
                GradientButton(
                  label: 'Take control of the browser',
                  icon: Icons.touch_app_rounded,
                  onTap: _connect,
                ),
                const SizedBox(height: 4),
                Center(
                  child: TextButton(
                    onPressed: _disconnect,
                    child: Text('Disconnect',
                        style: PT.label
                            .copyWith(color: P.err)),
                  ),
                ),
              ],
            ),
          ),
        ] else if (_streamState == BrowserStreamState.error ||
            _streamState == BrowserStreamState.disconnected) ...[
          const SizedBox(height: 12),
          PCard(
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: P.warn, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _streamError ?? 'The stream disconnected.',
                    style: PT.small.copyWith(color: P.inkSecondary),
                  ),
                ),
                TextButton(
                  onPressed: _connect,
                  child: Text('Reconnect',
                      style: PT.label.copyWith(color: P.accent)),
                ),
              ],
            ),
          ),
        ],
        if (_streamState != null) ...[
          const SizedBox(height: 12),
          _buildViewer(),
          if (live) ...[
            const SizedBox(height: 12),
            _buildTypeBar(),
            const SizedBox(height: 12),
            _buildScrollRow(),
            const SizedBox(height: 12),
            _buildNavBar(),
          ],
        ],
      ],
    );
  }

  Widget _buildViewer() {
    final frame = _frame;
    final connecting =
        _streamState == BrowserStreamState.connecting;
    // On stream error the last frame lingers: dim it and mark it stale
    // so it can't be mistaken for a live view.
    final stale = frame != null &&
        (_streamState == BrowserStreamState.error ||
            _streamState == BrowserStreamState.disconnected);
    return PCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(P.r16),
        child: AspectRatio(
          aspectRatio: (_imgW != null && _imgH != null && _imgH! > 0)
              ? _imgW! / _imgH!
              : 16 / 10,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (frame != null)
                LayoutBuilder(
                  builder: (context, box) => GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) => _onTapImage(d, box),
                    child: Image.memory(frame,
                        fit: BoxFit.fill, gaplessPlayback: true),
                  ),
                )
              else
                Container(
                  color: P.tonal,
                  child: Center(
                    child: connecting
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(
                                  color: P.accent),
                              const SizedBox(height: 12),
                              Text('Getting control…',
                                  style: PT.label),
                              const SizedBox(height: 4),
                              Text(_session, style: PT.meta),
                            ],
                          )
                        : Text('Waiting for frames…',
                            style: PT.meta),
                  ),
                ),
              if (stale)
                Positioned.fill(
                  child: Container(
                    color: Colors.black54,
                    alignment: Alignment.center,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: P.warn.withValues(alpha: 0.6)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              size: 16, color: P.warn),
                          const SizedBox(width: 8),
                          Text('Stale — stream dropped',
                              style: PT.small.copyWith(color: P.warn)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTypeBar() {
    return PCard(
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _typeCtrl,
              style: PT.body,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendType(),
              decoration:
                  _fieldDecoration('Type into the page…'),
            ),
          ),
          const SizedBox(width: 10),
          _ControlButton(
            icon: Icons.send_rounded,
            onTap: _sending ? null : _sendType,
          ),
        ],
      ),
    );
  }

  Widget _buildScrollRow() {
    return PCard(
      child: Row(
        children: [
          Expanded(
              child: Text('Scroll', style: PT.label)),
          _ControlButton(
            icon: Icons.keyboard_arrow_up_rounded,
            onTap: _sending
                ? null
                : () => _sendInput(
                    {'action': 'scroll', 'dx': 0, 'dy': -400}),
          ),
          const SizedBox(width: 10),
          _ControlButton(
            icon: Icons.keyboard_arrow_down_rounded,
            onTap: _sending
                ? null
                : () => _sendInput(
                    {'action': 'scroll', 'dx': 0, 'dy': 400}),
          ),
        ],
      ),
    );
  }

  Widget _buildNavBar() {
    return PCard(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _urlCtrl,
                  style: PT.body.copyWith(fontSize: 13),
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.go,
                  onSubmitted: (_) => _navigate(),
                  decoration: _fieldDecoration('https://…'),
                ),
              ),
              const SizedBox(width: 10),
              _ControlButton(
                icon: Icons.arrow_forward_rounded,
                onTap: _sending ? null : _navigate,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _NavAction(
                  icon: Icons.arrow_back_rounded,
                  label: 'Back',
                  onTap: _sending
                      ? null
                      : () => _sendInput({'action': 'back'})),
              _NavAction(
                  icon: Icons.arrow_forward_rounded,
                  label: 'Forward',
                  onTap: _sending
                      ? null
                      : () => _sendInput({'action': 'forward'})),
              _NavAction(
                  icon: Icons.refresh_rounded,
                  label: 'Reload',
                  onTap: _sending
                      ? null
                      : () => _sendInput({'action': 'reload'})),
            ],
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: PT.meta,
      filled: true,
      fillColor: P.tonal,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
    );
  }
}

/// Status dot for the stream state.
class _LiveDot extends StatelessWidget {
  final bool live;
  const _LiveDot({required this.live});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: live ? P.ok : P.inkFaint,
      ),
    );
  }
}

/// Round tonal icon button used by the take-control rows.
class _ControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _ControlButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: onTap == null ? P.tonal : P.accentSoft,
          border: Border.all(
              color: onTap == null
                  ? P.border
                  : P.accent.withValues(alpha: 0.4)),
        ),
        child: Icon(icon,
            size: 20,
            color: onTap == null ? P.inkFaint : P.accent),
      ),
    );
  }
}

class _NavAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _NavAction(
      {required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 22,
                color: onTap == null ? P.inkFaint : P.inkSecondary),
            const SizedBox(height: 2),
            Text(label,
                style: PT.meta.copyWith(
                    color:
                        onTap == null ? P.inkFaint : P.inkMuted)),
          ],
        ),
      ),
    );
  }
}
