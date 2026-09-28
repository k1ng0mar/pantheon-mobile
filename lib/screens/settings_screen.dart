import 'package:flutter/material.dart';

import '../services/pantheon_api.dart';
import '../services/settings_store.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/chips.dart';
import '../widgets/pantheon_card.dart';
import '../widgets/states.dart';
import 'connect_screen.dart';

class SettingsScreen extends StatelessWidget {
  final PantheonApi api;
  final ConnectionSettings settings;
  final VoidCallback onSignOut;
  final void Function(PantheonApi newApi) onReconnect;

  const SettingsScreen({
    super.key,
    required this.api,
    required this.settings,
    required this.onSignOut,
    required this.onReconnect,
  });

  @override
  Widget build(BuildContext context) {
    final tail = settings.token.length > 4
        ? settings.token.substring(settings.token.length - 4)
        : '';
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          const Overline('Connection'),
          PRowCard(
            rows: [
              PRow(
                title: 'Dashboard',
                subtitle: settings.baseUrl,
                dotColor: P.ok,
                trailing: const Icon(Icons.chevron_right_rounded,
                    color: P.inkFaint, weight: 1.6),
                onTap: () => _editConnection(context),
              ),
              PRow(
                title: 'Token',
                subtitle: '••••••••$tail',
                dotColor: P.inkFaint,
                trailing: const Icon(Icons.chevron_right_rounded,
                    color: P.inkFaint, weight: 1.6),
                onTap: () => _editConnection(context),
              ),
            ],
          ),
          const Overline('Actions'),
          PCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                InkWell(
                  onTap: () => _editConnection(context),
                  borderRadius: BorderRadius.circular(P.r16),
                  child: const Padding(
                    padding: EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Icon(Icons.link_rounded,
                            color: P.accent, size: 20, weight: 1.6),
                        SizedBox(width: 12),
                        Text('Edit connection', style: PT.rowTitle),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1, thickness: 1, indent: 46),
                InkWell(
                  onTap: () => _confirmSignOut(context),
                  borderRadius: BorderRadius.circular(P.r16),
                  child: const Padding(
                    padding: EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Icon(Icons.logout_rounded,
                            color: P.err, size: 20, weight: 1.6),
                        SizedBox(width: 12),
                        Text('Sign out',
                            style: TextStyle(
                                color: P.err,
                                fontWeight: FontWeight.w600,
                                fontSize: 15)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Overline('About'),
          const PCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pantheon', style: PT.rowTitle),
                SizedBox(height: 6),
                Text(
                  'Mobile companion for the Pantheon agent runtime — durable runs, approvals, usage and schedules. Talks to the dashboard API over your LAN; the token never leaves your device.',
                  style: PT.small,
                ),
                SizedBox(height: 8),
                Text('v0.1.0', style: PT.faint),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _editConnection(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConnectScreen(
          initialBaseUrl: settings.baseUrl,
          initialToken: settings.token,
          onConnected: (url, token) async {
            onReconnect(PantheonApi(baseUrl: url, token: token));
            if (context.mounted) Navigator.of(context).pop();
          },
        ),
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final ok = await showPSheet<bool>(
      context,
      SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SheetHandle(),
              const SizedBox(height: 8),
              const Text('Sign out?', style: PT.sectionTitle),
              const SizedBox(height: 8),
              const Text(
                'This forgets the dashboard URL and token on this device.',
                style: PT.small,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TonalButton(
                        label: 'Cancel',
                        onTap: () => Navigator.pop(context, false)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: PillButton(
                      label: 'Sign out',
                      color: P.err,
                      onTap: () => Navigator.pop(context, true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (ok == true) onSignOut();
  }
}
