import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/pantheon_api.dart';
import '../theme.dart';
import '../widgets/chips.dart';
import '../widgets/pantheon_card.dart';
import '../widgets/states.dart';

/// OAuth: connected-app status across providers with host-login guidance.
///
/// Backend: `GET /api/oauth/status` (local-first OAuth tokens in the
/// secrets vault). The OAuth dance itself needs the host browser
/// (loopback flow), so a disconnected provider shows guidance to run
/// `pantheon oauth login <app>` on the host — the phone never attempts
/// the flow.
class OAuthScreen extends StatefulWidget {
  final PantheonApi api;

  const OAuthScreen({super.key, required this.api});

  @override
  State<OAuthScreen> createState() => _OAuthScreenState();
}

class _OAuthScreenState extends State<OAuthScreen> {
  Future<OAuthStatus>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() => _future = widget.api.oauthStatus());
  }

  String _expiryText(OAuthProviderStatus p) {
    if (!p.connected) return 'Not connected';
    if (p.expired) return 'Token expired — re-login on the host';
    final e = p.expiresAt;
    if (e == null) return 'Connected · no expiry';
    final diff = e.difference(DateTime.now());
    if (diff.inDays >= 1) return 'Connected · expires in ${diff.inDays}d';
    if (diff.inHours >= 1) return 'Connected · expires in ${diff.inHours}h';
    return 'Connected · expires in ${diff.inMinutes}m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connected apps'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded,
                color: P.inkSecondary, weight: 1.6),
            onPressed: _load,
          ),
        ],
      ),
      body: FutureBuilder<OAuthStatus>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(
                child: CircularProgressIndicator(color: P.accent));
          }
          if (snap.hasError) {
            return EmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'Couldn\'t load OAuth status',
              body: snap.error.toString(),
              ctaLabel: 'Retry',
              onCta: _load,
            );
          }
          final providers = snap.data!.ordered;
          if (providers.isEmpty) {
            return EmptyState(
              icon: Icons.cable_outlined,
              title: 'No providers configured',
              body: 'The backend reports no OAuth providers.',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: providers.length,
            itemBuilder: (context, i) {
              final p = providers[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: PCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              p.displayName,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          StatusChip(
                            label: p.connected
                                ? (p.expired ? 'Expired' : 'Connected')
                                : 'Not connected',
                            color: p.connected && !p.expired
                                ? P.ok
                                : p.connected
                                    ? P.warn
                                    : P.inkSecondary,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _expiryText(p),
                        style: TextStyle(
                          fontSize: 13,
                          color: P.inkSecondary,
                        ),
                      ),
                      if (p.scopes.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final s in p.scopes)
                              PillChip(label: s, selected: false),
                          ],
                        ),
                      ],
                      if (!p.connected || p.expired) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Run `pantheon oauth login ${p.id}` on the host '
                          'to connect (the login needs the host browser).',
                          style: TextStyle(
                            fontSize: 12,
                            color: P.inkSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
