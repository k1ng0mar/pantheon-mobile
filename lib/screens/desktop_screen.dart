import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/desktop_stream_client.dart';
import '../services/pantheon_api.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/forms.dart';
import '../widgets/pantheon_card.dart';
import '../widgets/states.dart';

/// Bot Screen: live view of the desktop the CUA driver operates, with
/// human takeover for auth walls (login, 2FA, CAPTCHA).
///
/// Backend: `GET /api/desktop/status`, `GET /api/desktop/stream` (WS),
/// `POST /api/desktop/{takeover,heartbeat,input,release}`
/// (see `pantheon-dashboard/src/desktop.rs`).
///
/// While a lease is held, the agent's computer-use tools are parked
/// server-side; frames go to this viewer only and never enter model
/// context.
class DesktopScreen extends StatefulWidget {
  final PantheonApi api;

  const DesktopScreen({super.key, required this.api});

  @override
  State<DesktopScreen> createState() => _DesktopScreenState();
}

class _DesktopScreenState extends State<DesktopScreen> {
  Future<DesktopStatus>? _statusFuture;

  DesktopStreamClient? _client;
  StreamSubscription<Uint8List>? _frameSub;
  StreamSubscription<DesktopStreamState>? _stateSub;

  Uint8List? _frame;
  int? _imgW;
  int? _imgH;
  bool _decoding = false;

  /// Null = not connected yet; otherwise the last stream lifecycle state.
  DesktopStreamState? _streamState;
  bool _streaming = false;
  double _fps = 2;

  /// Takeover lease held by this device (null = not controlling).
  String? _leaseId;
  bool _takingOver = false;
  bool _releasing = false;
  Timer? _heartbeatTimer;
  String? _heartbeatError;
  String? _releaseSummary;

  final _typeCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _reloadStatus();
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    _disconnect();
    _typeCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  void _reloadStatus() {
    setState(() {
      _statusFuture = widget.api.desktopStatus();
      _releaseSummary = null;
    });
  }

  Future<void> _disconnect() async {
    _streaming = false;
    await _frameSub?.cancel();
    await _stateSub?.cancel();
    _frameSub = null;
    _stateSub = null;
    final c = _client;
    _client = null;
    if (c != null) await c.dispose();
  }

  /// Best-effort release on the way out: never block dispose on it.
  Future<void> _releaseQuietly() async {
    final lease = _leaseId;
    if (lease == null) return;
    _leaseId = null;
    _heartbeatTimer?.cancel();
    try {
      await widget.api.desktopRelease(lease);
    } catch (_) {}
  }

  Future<void> _connect() async {
    await _disconnect();
    final client = DesktopStreamClient(
      baseUrl: widget.api.baseUrl,
      token: widget.api.token,
      fps: _fps.round(),
    );
    _client = client;
    _frameSub = client.frames.listen((bytes) {
      if (!mounted) return;
      setState(() => _frame = bytes);
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
        }).catchError((_) {
          _decoding = false;
        });
      }
    });
    _stateSub = client.state.listen((s) {
      if (!mounted) return;
      setState(() => _streamState = s);
    });
    setState(() => _streaming = true);
    try {
      await client.connect();
    } catch (e) {
      if (!mounted) return;
      toastError(context, e);
      await _disconnect();
      if (mounted) setState(() {});
    }
  }

  Future<void> _takeOver() async {
    final ok = await confirmAction(
      context,
      title: 'Take over the desktop?',
      body: 'The agent\'s computer-use tools will be parked while you '
          'control the desktop. Release when done so it can resume.',
      confirmLabel: 'Take over',
    );
    if (!ok || !mounted) return;
    setState(() {
      _takingOver = true;
      _heartbeatError = null;
    });
    try {
      final t = await widget.api.desktopTakeover();
      if (!mounted) return;
      setState(() => _leaseId = t.leaseId);
      // Heartbeat roughly every 10s; the server lets the lease lapse
      // after ~30s without one.
      _heartbeatTimer =
          Timer.periodic(const Duration(seconds: 10), (_) => _beat());
      _reloadStatus();
    } on DesktopHeldException catch (e) {
      if (mounted) toastError(context, e);
      if (mounted) _reloadStatus();
    } catch (e) {
      if (mounted) toastError(context, e);
    } finally {
      if (mounted) setState(() => _takingOver = false);
    }
  }

  Future<void> _beat() async {
    final lease = _leaseId;
    if (lease == null) return;
    try {
      await widget.api.desktopHeartbeat(lease);
      if (!mounted) return;
      if (_heartbeatError != null) setState(() => _heartbeatError = null);
    } catch (e) {
      // Honest state: the lease may have lapsed server-side. Stop
      // claiming control rather than sending input into the void.
      if (!mounted) return;
      _heartbeatTimer?.cancel();
      setState(() {
        _heartbeatError = 'Heartbeat failed — control may be lost. '
            'Release and take over again.';
        _leaseId = null;
      });
      _reloadStatus();
    }
  }

  Future<void> _release() async {
    final lease = _leaseId;
    if (lease == null || _releasing) return;
    setState(() => _releasing = true);
    _heartbeatTimer?.cancel();
    try {
      final summary = await widget.api.desktopRelease(lease);
      if (!mounted) return;
      setState(() {
        _leaseId = null;
        _heartbeatError = null;
        _releaseSummary = summary.isEmpty ? null : summary;
      });
      toast(context, 'Desktop released.');
      _reloadStatus();
    } catch (e) {
      if (mounted) {
        // The lease stays ours locally; the server may already have
        // expired it — either way the next status poll tells the truth.
        toastError(context, e);
        _reloadStatus();
      }
    } finally {
      if (mounted) setState(() => _releasing = false);
    }
  }

  Future<void> _sendInput(Map<String, dynamic> action) async {
    final lease = _leaseId;
    if (lease == null || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.api.desktopInput({'lease_id': lease, ...action});
    } catch (e) {
      if (mounted) toastError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _onTapImage(TapDownDetails d, BoxConstraints box) {
    if (_leaseId == null || _streamState != DesktopStreamState.live) return;
    final w = _imgW;
    final h = _imgH;
    if (w == null || h == null || w <= 0 || h <= 0) return;
    // The image fills the AspectRatio box exactly, so fractions map
    // linearly onto desktop pixels.
    final fx = (d.localPosition.dx / box.maxWidth).clamp(0.0, 1.0);
    final fy = (d.localPosition.dy / box.maxHeight).clamp(0.0, 1.0);
    _sendInput({
      'action': 'click',
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

  void _sendKey() {
    final key = _keyCtrl.text.trim();
    if (key.isEmpty) return;
    _keyCtrl.clear();
    _sendInput({'action': 'press', 'key': key});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bot Screen'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded,
                color: P.inkSecondary, weight: 1.6),
            onPressed: _reloadStatus,
          ),
        ],
      ),
      body: FutureBuilder<DesktopStatus>(
        future: _statusFuture,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(
                child: CircularProgressIndicator(color: P.accent));
          }
          if (snap.hasError) {
            return EmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'Couldn\'t load desktop status',
              body: snap.error.toString(),
              ctaLabel: 'Retry',
              onCta: _reloadStatus,
            );
          }
          final st = snap.data!;
          if (!st.enabled) {
            return const EmptyState(
              icon: Icons.desktop_access_disabled_outlined,
              title: 'Desktop control is off',
              body: 'Enable the CUA driver on the host to watch and '
                  'take over its desktop.',
            );
          }
          return _buildBody(st);
        },
      ),
    );
  }

  Widget _buildBody(DesktopStatus st) {
    final controlling = _leaseId != null;
    final heldElsewhere = !controlling && st.taken;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        PCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Driver: ${st.driver}',
                        style: const TextStyle(fontSize: 13)),
                    const SizedBox(height: 4),
                    Text(
                      controlling
                          ? 'You are controlling the desktop'
                          : st.taken
                              ? 'Controlled by ${st.controller}'
                              : 'Agent-driven · ${st.viewers} watching',
                      style: TextStyle(
                          fontSize: 13, color: P.inkSecondary),
                    ),
                  ],
                ),
              ),
              if (controlling)
                PillButton(
                  label: _releasing ? 'Releasing…' : 'Release',
                  onTap: _releasing ? null : _release,
                  color: P.warn,
                )
              else
                PillButton(
                  label: _takingOver ? 'Taking over…' : 'Take over',
                  onTap: (_takingOver || heldElsewhere) ? null : _takeOver,
                ),
            ],
          ),
        ),
        if (heldElsewhere) ...[
          const SizedBox(height: 8),
          Text(
            'Takeover is disabled while ${st.controller} holds the lease.',
            style:
                TextStyle(fontSize: 12, color: P.inkSecondary),
          ),
        ],
        if (_heartbeatError != null) ...[
          const SizedBox(height: 8),
          Text(_heartbeatError!,
              style: TextStyle(fontSize: 12, color: P.warn)),
        ],
        if (_releaseSummary != null) ...[
          const SizedBox(height: 8),
          PCard(
            child: Text(_releaseSummary!,
                style: const TextStyle(fontSize: 13)),
          ),
        ],
        const SizedBox(height: 12),
        if (!_streaming)
          Center(
            child: PillButton(
              label: 'Watch live',
              onTap: _connect,
            ),
          )
        else
          _buildViewer(controlling),
        if (controlling) ...[
          const SizedBox(height: 12),
          _buildInputRow(),
        ],
      ],
    );
  }

  Widget _buildViewer(bool controlling) {
    final frame = _frame;
    final live = _streamState == DesktopStreamState.live;
    return Column(
      children: [
        AspectRatio(
          aspectRatio: (_imgW != null && _imgH != null && _imgH! > 0)
              ? _imgW! / _imgH!
              : 16 / 9,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: P.borderStrong),
              color: Colors.black,
            ),
            child: frame == null
                ? Center(
                    child: live
                        ? CircularProgressIndicator(color: P.accent)
                        : Text('Connecting…',
                            style: TextStyle(color: P.inkSecondary)),
                  )
                : LayoutBuilder(
                    builder: (context, box) => GestureDetector(
                      onTapDown: controlling
                          ? (d) => _onTapImage(d, box)
                          : null,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(frame,
                            fit: BoxFit.fill,
                            gaplessPlayback: true),
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              live ? 'Live' : 'Connecting…',
              style: TextStyle(fontSize: 12, color: P.inkSecondary),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 120,
              child: Row(
                children: [
                  Text('fps',
                      style:
                          TextStyle(fontSize: 12, color: P.inkSecondary)),
                  Expanded(
                    child: Slider(
                      value: _fps,
                      min: 1,
                      max: 10,
                      divisions: 9,
                      label: _fps.round().toString(),
                      onChanged: (v) => setState(() => _fps = v),
                      onChangeEnd: (_) {
                        if (_streaming) _connect();
                      },
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () async {
                await _releaseQuietly();
                await _disconnect();
                if (mounted) setState(() {});
              },
              child: const Text('Stop'),
            ),
          ],
        ),
        if (controlling)
          Text(
            'Tap the screen to click while controlling.',
            style: TextStyle(fontSize: 12, color: P.inkSecondary),
          ),
      ],
    );
  }

  Widget _buildInputRow() {
    return PCard(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _typeCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Type text…',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _sendType(),
                ),
              ),
              const SizedBox(width: 8),
              PillButton(label: 'Type', onTap: _sendType),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _keyCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Key (Enter, Tab, Escape…)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _sendKey(),
                ),
              ),
              const SizedBox(width: 8),
              PillButton(label: 'Press', onTap: _sendKey),
            ],
          ),
        ],
      ),
    );
  }
}
