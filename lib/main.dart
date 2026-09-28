import 'package:flutter/material.dart';

import 'screens/approvals_screen.dart';
import 'screens/connect_screen.dart';
import 'screens/home_screen.dart';
import 'screens/runs_screen.dart';
import 'screens/schedule_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/stats_screen.dart';
import 'services/pantheon_api.dart';
import 'services/settings_store.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PantheonApp());
}

class PantheonApp extends StatefulWidget {
  const PantheonApp({super.key});

  @override
  State<PantheonApp> createState() => _PantheonAppState();
}

class _PantheonAppState extends State<PantheonApp> {
  final _store = SettingsStore();
  ConnectionSettings? _settings;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final s = await _store.load();
    // Brief branded beat so the splash reads as intentional, not a flash.
    await Future.delayed(const Duration(milliseconds: 600));
    if (mounted) {
      setState(() {
        _settings = s;
        _loading = false;
      });
    }
  }

  Future<void> _onConnected(String baseUrl, String token) async {
    await _store.save(baseUrl, token);
    if (mounted) {
      setState(() {
        _settings = ConnectionSettings(baseUrl: baseUrl, token: token);
      });
    }
  }

  Future<void> _onSignOut() async {
    await _store.clear();
    if (mounted) {
      setState(() => _settings = const _EmptySettings());
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pantheon',
      theme: pantheonTheme(),
      debugShowCheckedModeBanner: false,
      home: _loading
          ? const _Splash()
          : (_settings != null && _settings!.isComplete)
              ? MainShell(
                  settings: _settings!,
                  onSignOut: _onSignOut,
                  onReconnect: (api) => _onConnected(api.baseUrl, api.token),
                )
              : ConnectScreen(onConnected: _onConnected),
    );
  }
}

class _EmptySettings extends ConnectionSettings {
  const _EmptySettings() : super(baseUrl: '', token: '');
}

/// Branded splash: gradient orb + wordmark, gentle scale-in.
class _Splash extends StatefulWidget {
  const _Splash();

  @override
  State<_Splash> createState() => _SplashState();
}

class _SplashState extends State<_Splash> {
  bool _in = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => mounted ? setState(() => _in = true) : null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: AnimatedScale(
          scale: _in ? 1 : 0.92,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: _in ? 1 : 0,
            duration: const Duration(milliseconds: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    gradient: P.gradient,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Text('P',
                      style: TextStyle(
                          fontFamily: PT.displayFamily,
                          fontSize: 34,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                ),
                const SizedBox(height: 16),
                const Text('Pantheon', style: PT.screenTitle),
                const SizedBox(height: 4),
                Text('your runtime, in your pocket',
                    style: PT.small.copyWith(color: P.inkMuted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  final ConnectionSettings settings;
  final VoidCallback onSignOut;
  final void Function(PantheonApi api) onReconnect;

  const MainShell({
    super.key,
    required this.settings,
    required this.onSignOut,
    required this.onReconnect,
  });

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _tab = 0;
  late PantheonApi _api;
  final _pendingApprovals = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _api = PantheonApi(
        baseUrl: widget.settings.baseUrl, token: widget.settings.token);
  }

  @override
  void didUpdateWidget(MainShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings.baseUrl != widget.settings.baseUrl ||
        oldWidget.settings.token != widget.settings.token) {
      _api = PantheonApi(
          baseUrl: widget.settings.baseUrl, token: widget.settings.token);
    }
  }

  @override
  void dispose() {
    _pendingApprovals.dispose();
    super.dispose();
  }

  void _onReconnect(PantheonApi api) {
    widget.onReconnect(api);
    setState(() => _api = api);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(api: _api, pendingApprovals: _pendingApprovals),
      RunsScreen(api: _api),
      ApprovalsScreen(api: _api, pendingApprovals: _pendingApprovals),
      StatsScreen(api: _api),
      MoreTab(
        api: _api,
        settings: widget.settings,
        onSignOut: widget.onSignOut,
        onReconnect: _onReconnect,
      ),
    ];
    return Scaffold(
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: ValueListenableBuilder<int>(
        valueListenable: _pendingApprovals,
        builder: (context, pending, _) => _NyxTabBar(
          index: _tab,
          pendingApprovals: pending,
          onTap: (i) => setState(() => _tab = i),
        ),
      ),
    );
  }
}

/// Nyx tab bar: 80dp, tonal bg, hairline top border,
/// active icon in a 64×32 accent-wash pill, thin-stroke icons.
class _NyxTabBar extends StatelessWidget {
  final int index;
  final int pendingApprovals;
  final ValueChanged<int> onTap;

  const _NyxTabBar({
    required this.index,
    required this.pendingApprovals,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const items = [
      _TabDef(Icons.home_outlined, Icons.home_rounded, 'Home'),
      _TabDef(Icons.bolt_outlined, Icons.bolt_rounded, 'Runs'),
      _TabDef(Icons.rule_outlined, Icons.rule_rounded, 'Approvals'),
      _TabDef(Icons.bar_chart_outlined, Icons.bar_chart_rounded, 'Usage'),
      _TabDef(Icons.more_horiz_rounded, Icons.more_horiz_rounded, 'More'),
    ];
    return Container(
      decoration: const BoxDecoration(
        color: P.tabBar,
        border: Border(top: BorderSide(color: P.border, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 80,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(child: _tabButton(items[i], i)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabButton(_TabDef def, int i) {
    final active = i == index;
    final icon = Icon(
      active ? def.activeIcon : def.icon,
      size: 23,
      weight: 1.6,
      color: active ? P.accent : P.inkSecondary,
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onTap(i),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: 64,
            height: 32,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: active ? P.accentSoft : Colors.transparent,
            ),
            alignment: Alignment.center,
            child: i == 2 && pendingApprovals > 0
                ? Badge(
                    label: Text('$pendingApprovals',
                        style: const TextStyle(
                            fontSize: 10, fontWeight: FontWeight.w600)),
                    backgroundColor: P.err,
                    textColor: Colors.white,
                    child: icon,
                  )
                : icon,
          ),
          const SizedBox(height: 4),
          Text(
            def.label,
            style: PT.faint.copyWith(
              color: active ? P.ink : P.inkSecondary,
              fontSize: 12,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class _TabDef {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const _TabDef(this.icon, this.activeIcon, this.label);
}

/// The "More" tab: Nyx-style hub list of Schedule / Settings.
class MoreTab extends StatelessWidget {
  final PantheonApi api;
  final ConnectionSettings settings;
  final VoidCallback onSignOut;
  final void Function(PantheonApi api) onReconnect;

  const MoreTab({
    super.key,
    required this.api,
    required this.settings,
    required this.onSignOut,
    required this.onReconnect,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _hubCard(
            context,
            icon: Icons.schedule_outlined,
            title: 'Schedule',
            subtitle: 'Recurring jobs and triggers',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ScheduleScreen(api: api)),
            ),
          ),
          const SizedBox(height: 12),
          _hubCard(
            context,
            icon: Icons.settings_outlined,
            title: 'Settings',
            subtitle: 'Connection, sign out, about',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SettingsScreen(
                  api: api,
                  settings: settings,
                  onSignOut: onSignOut,
                  onReconnect: onReconnect,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hubCard(BuildContext context,
      {required IconData icon,
      required String title,
      required String subtitle,
      required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(P.r16),
        splashColor: P.accentSoft,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: P.surface,
            borderRadius: BorderRadius.circular(P.r16),
            border: Border.all(color: P.border),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: P.accentSoft,
                  borderRadius: BorderRadius.circular(P.r14),
                ),
                child: Icon(icon, color: P.accent, size: 22, weight: 1.6),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: PT.rowTitle),
                    const SizedBox(height: 2),
                    Text(subtitle, style: PT.meta),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: P.inkFaint, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
