import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/pantheon_api.dart';
import '../theme.dart';
import '../widgets/buttons.dart';

/// First-run (and re-connect) screen: dashboard URL + token.
/// Hero: slow-drifting gradient orbs — the fun bit.
class ConnectScreen extends StatefulWidget {
  final String initialBaseUrl;
  final String initialToken;
  final Future<void> Function(String baseUrl, String token) onConnected;

  const ConnectScreen({
    super.key,
    this.initialBaseUrl = '',
    this.initialToken = '',
    required this.onConnected,
  });

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _url;
  late final TextEditingController _token;
  late final AnimationController _orb;
  bool _busy = false;
  String? _error;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(text: widget.initialBaseUrl);
    _token = TextEditingController(text: widget.initialToken);
    _orb =
        AnimationController(vsync: this, duration: const Duration(seconds: 14))
          ..repeat();
  }

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    _orb.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final baseUrl = _url.text.trim().replaceAll(RegExp(r'/$'), '');
    final token = _token.text.trim();
    if (baseUrl.isEmpty || token.isEmpty) {
      setState(() => _error = 'Enter both the dashboard URL and the token.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = PantheonApi(baseUrl: baseUrl, token: token);
      await api.overview(); // throws on bad URL / token
      await widget.onConnected(baseUrl, token);
    } on PantheonAuthException catch (e) {
      setState(() => _error = e.toString());
    } on PantheonUnreachableException catch (e) {
      setState(() => _error = e.toString());
    } on PantheonApiException catch (e) {
      setState(() => _error = e.toString());
    } catch (e) {
      setState(() => _error = 'Could not connect: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          AnimatedBuilder(
            animation: _orb,
            builder: (_, __) => CustomPaint(
              painter: _OrbPainter(_orb.value),
              size: Size.infinite,
            ),
          ),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
              children: [
                _Delayed(
                    index: 0,
                    child: const Text('Pantheon', style: PT.screenTitle)),
                _Delayed(
                    index: 1,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Your agent runtime, in your pocket.\nPoint the app at your dashboard to begin.',
                        style: PT.body.copyWith(color: P.inkSecondary),
                      ),
                    )),
                const SizedBox(height: 32),
                _Delayed(
                    index: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('DASHBOARD URL', style: PT.overline),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _url,
                          keyboardType: TextInputType.url,
                          autocorrect: false,
                          style: PT.body,
                          decoration: const InputDecoration(
                            hintText: 'http://192.168.1.10:7171',
                            prefixIcon: Icon(Icons.link_rounded,
                                color: P.inkFaint, weight: 1.6),
                          ),
                        ),
                      ],
                    )),
                const SizedBox(height: 20),
                _Delayed(
                    index: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('TOKEN', style: PT.overline),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _token,
                          obscureText: _obscure,
                          autocorrect: false,
                          style: PT.mono,
                          decoration: InputDecoration(
                            hintText: 'paste the dashboard token',
                            prefixIcon: const Icon(Icons.key_outlined,
                                color: P.inkFaint, weight: 1.6),
                            suffixIcon: IconButton(
                              icon: Icon(
                                  _obscure
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  color: P.inkFaint,
                                  weight: 1.6),
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'On your machine: pantheon dashboard --bind 0.0.0.0 --port 7171. The token is stored in your device keychain, never sent anywhere else.',
                          style: PT.faint.copyWith(height: 1.5),
                        ),
                      ],
                    )),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: P.err.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(P.r12),
                      border: Border.all(color: P.err.withValues(alpha: 0.4)),
                    ),
                    child:
                        Text(_error!, style: PT.small.copyWith(color: P.err)),
                  ),
                ],
                const SizedBox(height: 28),
                _Delayed(
                    index: 4,
                    child: _busy
                        ? const SizedBox(
                            height: 52,
                            child: Center(
                                child: SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2.5, color: P.accent))))
                        : GradientButton(
                            label: 'Connect',
                            icon: Icons.arrow_forward_rounded,
                            onTap: _connect,
                          )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Cascading entrance for the connect form.
class _Delayed extends StatefulWidget {
  final int index;
  final Widget child;

  const _Delayed({required this.index, required this.child});

  @override
  State<_Delayed> createState() => _DelayedState();
}

class _DelayedState extends State<_Delayed> {
  bool _show = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: 80 + widget.index * 90), () {
      if (mounted) setState(() => _show = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 450),
      opacity: _show ? 1 : 0,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
        offset: _show ? Offset.zero : const Offset(0, 0.18),
        child: widget.child,
      ),
    );
  }
}

/// Slow-drifting gradient orbs on the brand background.
class _OrbPainter extends CustomPainter {
  final double t;

  _OrbPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final orbs = [
      _OrbSpec(0.85, 0.12, 190, const Color(0xFF7223FF), 0.0),
      _OrbSpec(0.12, 0.72, 230, const Color(0xFF4B00CD), 2.1),
      _OrbSpec(0.75, 0.85, 150, const Color(0xFF8B5CFF), 4.2),
    ];
    for (final o in orbs) {
      final dx = math.sin((t * math.pi * 2) + o.phase) * 34;
      final dy = math.cos((t * math.pi * 2 * 0.7) + o.phase) * 44;
      final c = Offset(size.width * o.x + dx, size.height * o.y + dy);
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [o.color.withValues(alpha: 0.42), Colors.transparent],
        ).createShader(Rect.fromCircle(center: c, radius: o.r));
      canvas.drawCircle(c, o.r, paint);
    }
  }

  @override
  bool shouldRepaint(_OrbPainter old) => old.t != t;
}

class _OrbSpec {
  final double x, y, r, phase;
  final Color color;

  _OrbSpec(this.x, this.y, this.r, this.color, this.phase);
}
