import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/pantheon_api.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/forms.dart';
import '../widgets/pantheon_card.dart';
import '../widgets/states.dart';

/// Website logins: credentials the browser tool can use to sign in to
/// sites. Passwords are stored server-side and never returned by the API —
/// the app only ever shows the masked placeholder, never the secret.
class LoginsScreen extends StatefulWidget {
  final PantheonApi api;

  const LoginsScreen({super.key, required this.api});

  @override
  State<LoginsScreen> createState() => _LoginsScreenState();
}

class _LoginsScreenState extends State<LoginsScreen> {
  Future<List<LoginEntry>>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() => _future = widget.api.listLogins());
  }

  Future<void> _add() async {
    final result = await _loginSheet(context, entry: null);
    if (result == null || !mounted) return;
    try {
      await widget.api.createLogin(result.site, result.username, result.password!);
      if (!mounted) return;
      toast(context, 'Login saved.');
      _load();
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  Future<void> _edit(LoginEntry entry) async {
    final result = await _loginSheet(context, entry: entry);
    if (result == null || !mounted) return;
    try {
      await widget.api.updateLogin(
        entry.id,
        site: result.site,
        username: result.username,
        // Only sent when the user typed a new password; the sheet
        // leaves it null otherwise.
        password: result.password,
      );
      if (!mounted) return;
      toast(context, 'Login updated.');
      _load();
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  Future<void> _delete(LoginEntry entry) async {
    final ok = await confirmAction(
      context,
      title: 'Delete this login?',
      body: '“${entry.username} @ ${entry.site}” will be removed. '
          'The browser tool will no longer be able to sign in there.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await widget.api.deleteLogin(entry.id);
      if (!mounted) return;
      toast(context, 'Login deleted.');
      _load();
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Website logins'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded,
                color: P.inkSecondary, weight: 1.6),
            onPressed: _load,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        backgroundColor: P.accentDeep,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded, weight: 2),
        label:
            const Text('Add', style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: FutureBuilder<List<LoginEntry>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return _skeleton();
          }
          if (snap.hasError) {
            return EmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'Couldn\'t load logins',
              body: snap.error.toString(),
              ctaLabel: 'Retry',
              onCta: _load,
            );
          }
          final logins = snap.data!;
          if (logins.isEmpty) {
            return const EmptyState(
              icon: Icons.lock_outline_rounded,
              title: 'No logins saved',
              body: 'Save website credentials here and the browser tool '
                  'can sign in to those sites for you. Passwords are '
                  'stored server-side and never displayed.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => _load(),
            color: P.accent,
            backgroundColor: P.surface,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
              itemCount: logins.length + 1,
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12, top: 4),
                    child: Text(
                      'Passwords are stored server-side and never displayed.',
                      style: PT.meta,
                    ),
                  );
                }
                final entry = logins[i - 1];
                return StaggerItem(index: i, child: _card(entry));
              },
            ),
          );
        },
      ),
    );
  }

  Widget _card(LoginEntry e) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.site,
                          style: PT.body.copyWith(
                              fontWeight: FontWeight.w600, fontSize: 14)),
                      const SizedBox(height: 2),
                      Text(e.username,
                          style: PT.meta.copyWith(fontSize: 12.5)),
                    ],
                  ),
                ),
                Text('••••••',
                    style: PT.mono.copyWith(color: P.inkFaint, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: PillButton(
                    label: 'Edit',
                    filled: false,
                    onTap: () => _edit(e),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: PillButton(
                    label: 'Delete',
                    filled: false,
                    color: P.err,
                    onTap: () => _delete(e),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _skeleton() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: 5,
      itemBuilder: (_, __) => const Padding(
        padding: EdgeInsets.only(bottom: 10),
        child: Shimmer(width: double.infinity, height: 110, radius: 16),
      ),
    );
  }
}

/// Result of the add/edit sheet. [password] is null when the user left
/// the field blank while editing (keep the stored password); it is
/// always non-null when adding.
class _LoginFormResult {
  final String site;
  final String username;
  final String? password;

  _LoginFormResult(
      {required this.site, required this.username, this.password});
}

Future<_LoginFormResult?> _loginSheet(BuildContext context,
    {LoginEntry? entry}) async {
  final editing = entry != null;
  final siteCtrl = TextEditingController(text: entry?.site ?? '');
  final userCtrl = TextEditingController(text: entry?.username ?? '');
  final passCtrl = TextEditingController();
  var obscure = true;
  var busy = false;
  try {
    return await showPSheet<_LoginFormResult>(
      context,
      StatefulBuilder(
        builder: (ctx, setSheet) {
          Future<void> submit() async {
            final site = siteCtrl.text.trim();
            final username = userCtrl.text.trim();
            final password = passCtrl.text;
            if (site.isEmpty || username.isEmpty) {
              toast(ctx, 'Site and username are required.');
              return;
            }
            if (!editing && password.isEmpty) {
              toast(ctx, 'A password is required for a new login.');
              return;
            }
            setSheet(() => busy = true);
            try {
              Navigator.pop(
                ctx,
                _LoginFormResult(
                  site: site,
                  username: username,
                  password: password.isEmpty ? null : password,
                ),
              );
            } finally {
              if (ctx.mounted) setSheet(() => busy = false);
            }
          }

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  20, 8, 20, 24 + MediaQuery.of(ctx).viewInsets.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SheetHandle(),
                  const SizedBox(height: 8),
                  Text(editing ? 'Edit login' : 'Add login',
                      style: PT.sectionTitle),
                  const SizedBox(height: 4),
                  Text(
                    'Passwords are stored on the runtime and never shown again.',
                    style: PT.meta,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: siteCtrl,
                    autofocus: !editing,
                    style: PT.body,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Site',
                      hintText: 'e.g. example.com',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: userCtrl,
                    style: PT.body,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      hintText: 'Account username or email',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passCtrl,
                    style: PT.body,
                    obscureText: obscure,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      hintText: editing ? 'Leave blank to keep' : null,
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: P.inkSecondary,
                        ),
                        onPressed: () =>
                            setSheet(() => obscure = !obscure),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: TonalButton(
                          label: 'Cancel',
                          onTap: () => Navigator.pop(ctx),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: busy ? null : submit,
                          style: FilledButton.styleFrom(
                            backgroundColor: P.accentDeep,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(0, 52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(P.r20),
                            ),
                          ),
                          child: busy
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(editing ? 'Save' : 'Add login',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  } finally {
    siteCtrl.dispose();
    userCtrl.dispose();
    passCtrl.dispose();
  }
}
