import 'dart:async';

import 'package:flutter/material.dart';

import 'screens/appearance_screen.dart';
import 'screens/approvals_screen.dart';
import 'screens/browser_screen.dart';
import 'screens/config_screen.dart';
import 'screens/connect_screen.dart';
import 'screens/experts_screen.dart';
import 'screens/gateway_screen.dart';
import 'screens/home_screen.dart';
import 'screens/ideas_screen.dart';
import 'screens/keys_screen.dart';
import 'screens/logins_screen.dart';
import 'screens/logs_screen.dart';
import 'screens/mcp_screen.dart';
import 'screens/memory_screen.dart';
import 'screens/models_screen.dart';
import 'screens/nightly_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/plugins_screen.dart';
import 'screens/profiles_screen.dart';
import 'screens/sessions_screen.dart';
import 'screens/schedule_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/skills_screen.dart';
import 'screens/stats_screen.dart';
import 'screens/swarm_screen.dart';
import 'screens/voice_settings_screen.dart';
import 'services/app_preferences.dart';
import 'services/pantheon_api.dart';
import 'services/settings_store.dart';
import 'widgets/in_app_banner.dart';
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
  final _prefs = AppPreferences.instance;
  ConnectionSettings? _settings;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _prefs.appearance.addListener(_onAppearanceChanged);
    _boot();
  }

  @override
  void dispose() {
    _prefs.appearance.removeListener(_onAppearanceChanged);
    super.dispose();
  }

  void _onAppearanceChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _boot() async {
    final s = await _store.load();
    await _prefs.init();
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
    // Resolve the live brightness, select the palette + custom colors,
    // then build both theme variants so they read this frame's values.
    final themeMode = _prefs.themeMode.value;
    final platformBrightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    final brightness = themeMode == ThemeMode.system
        ? platformBrightness
        : (themeMode == ThemeMode.light
            ? Brightness.light
            : Brightness.dark);
    final compact = _prefs.compactDensity.value;
    P.apply(brightness);
    P.setCustomColors(
      accent: _prefs.customAccent.value,
      bg: _prefs.customBg.value,
      surface: _prefs.customSurface.value,
      tonal: _prefs.customTonal.value,
    );
    final lightTheme = pantheonTheme(Brightness.light, compact: compact);
    final darkTheme = pantheonTheme(Brightness.dark, compact: compact);
    // pantheonTheme() re-applies its own brightness; restore the live one.
    P.apply(brightness);
    return MaterialApp(
      title: 'Pantheon',
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: themeMode,
      debugShowCheckedModeBanner: false,
      builder: (ctx, child) {
        final mq = MediaQuery.of(ctx);
        return MediaQuery(
          data: mq.copyWith(
              textScaler: TextScaler.linear(_prefs.textScale.value)),
          child: child!,
        );
      },
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
    final reduceMotion = AppPreferences.instance.reduceMotion.value;
    final content = Column(
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
        Text('Pantheon', style: PT.screenTitle),
        const SizedBox(height: 4),
        Text('your runtime, in your pocket',
            style: PT.small.copyWith(color: P.inkMuted)),
      ],
    );
    if (reduceMotion) {
      return Scaffold(body: Center(child: content));
    }
    return Scaffold(
      body: Center(
        child: AnimatedScale(
          scale: _in ? 1 : 0.92,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: _in ? 1 : 0,
            duration: const Duration(milliseconds: 400),
            child: content,
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

  /// Approvals watcher: polls the approvals list so a pending approval
  /// surfaces an in-app banner even when the Approvals screen (now in
  /// the More hub) isn't open. First poll seeds the seen set; later
  /// polls banner only for newly parked approvals.
  Timer? _approvalWatch;
  final Set<String> _seenApprovalIds = {};
  bool _approvalWatchSeeded = false;

  @override
  void initState() {
    super.initState();
    _api = PantheonApi(
        baseUrl: widget.settings.baseUrl, token: widget.settings.token);
    _approvalWatch =
        Timer.periodic(const Duration(seconds: 15), (_) => _watchApprovals());
    _watchApprovals();
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
    _approvalWatch?.cancel();
    _pendingApprovals.dispose();
    super.dispose();
  }

  /// Poll the approvals list: keep the pending count fresh and raise an
  /// in-app banner for newly parked approvals. Silent on failure — the
  /// next tick retries.
  Future<void> _watchApprovals() async {
    try {
      final list = await _api.approvals();
      if (!mounted) return;
      _pendingApprovals.value = list.length;
      if (!_approvalWatchSeeded) {
        _seenApprovalIds.addAll(list.map((a) => a.id));
        _approvalWatchSeeded = true;
        return;
      }
      for (final a in list) {
        if (_seenApprovalIds.add(a.id)) {
          InAppBanner.showApproval(
            title: 'Approval needed',
            body:
                '${a.displayRun} is parked waiting for your decision.',
            sessionId: a.runId.isNotEmpty ? a.runId : null,
            onTap: () {
              InAppBanner.dismiss();
              Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ApprovalsScreen(
                      api: _api,
                      pendingApprovals: _pendingApprovals)));
            },
          );
        }
      }
    } catch (_) {}
  }

  void _onReconnect(PantheonApi api) {
    widget.onReconnect(api);
    setState(() => _api = api);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(api: _api, pendingApprovals: _pendingApprovals),
      SessionsScreen(api: _api, pendingApprovals: _pendingApprovals),
      ScheduleScreen(api: _api),
      StatsScreen(api: _api),
      MoreTab(
        api: _api,
        settings: widget.settings,
        onSignOut: widget.onSignOut,
        onReconnect: _onReconnect,
        pendingApprovals: _pendingApprovals,
      ),
    ];
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(index: _tab, children: pages),
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: InAppBannerHost(),
          ),
        ],
      ),
      bottomNavigationBar: _NyxTabBar(
        index: _tab,
        onTap: (i) => setState(() => _tab = i),
      ),
    );
  }
}

/// Nyx tab bar: 80dp, tonal bg, hairline top border,
/// active icon in a 64×32 accent-wash pill, thin-stroke icons.
class _NyxTabBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;

  const _NyxTabBar({
    required this.index,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const items = [
      _TabDef(Icons.home_outlined, Icons.home_rounded, 'Home'),
      _TabDef(Icons.forum_outlined, Icons.forum_rounded, 'Sessions'),
      _TabDef(Icons.schedule_outlined, Icons.schedule_rounded, 'Tasks'),
      _TabDef(Icons.bar_chart_outlined, Icons.bar_chart_rounded, 'Usage'),
      _TabDef(Icons.more_horiz_rounded, Icons.more_horiz_rounded, 'More'),
    ];
    return Container(
      decoration:  BoxDecoration(
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
            child: icon,
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

/// The "More" tab: Nyx-style hub for the full control plane —
/// tasks, profiles, models, memory, skills, plugins, MCP, configs,
/// keys, logs, gateway, and app settings.
class MoreTab extends StatelessWidget {
  final PantheonApi api;
  final ConnectionSettings settings;
  final VoidCallback onSignOut;
  final void Function(PantheonApi api) onReconnect;
  final ValueNotifier<int> pendingApprovals;

  const MoreTab({
    super.key,
    required this.api,
    required this.settings,
    required this.onSignOut,
    required this.onReconnect,
    required this.pendingApprovals,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const _HubSection('Control'),
          ValueListenableBuilder<int>(
            valueListenable: pendingApprovals,
            builder: (context, pending, _) => _hubCard(
              context,
              icon: Icons.rule_outlined,
              title: 'Approvals',
              subtitle: pending > 0
                  ? '$pending waiting for your decision'
                  : 'No pending decisions',
              trailing: pending > 0
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: P.err,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text('$pending',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                    )
                  : null,
              onTap: () => _push(
                  context,
                  ApprovalsScreen(
                      api: api, pendingApprovals: pendingApprovals)),
            ),
          ),
          const SizedBox(height: 12),
          _hubCard(
            context,
            icon: Icons.schedule_outlined,
            title: 'Tasks',
            subtitle: 'Scheduled jobs, triggers, templates',
            onTap: () => _push(context, ScheduleScreen(api: api)),
          ),
          const SizedBox(height: 12),
          _hubCard(
            context,
            icon: Icons.hub_outlined,
            title: 'Gateway',
            subtitle: 'Always-on service status and restart',
            onTap: () => _push(context, GatewayScreen(api: api)),
          ),
          const SizedBox(height: 12),
          _hubCard(
            context,
            icon: Icons.nights_stay_outlined,
            title: 'Nightly repair',
            subtitle: 'Repair loop status and toggle',
            onTap: () => _push(context, NightlyScreen(api: api)),
          ),
          const SizedBox(height: 12),
          _hubCard(
            context,
            icon: Icons.alt_route_outlined,
            title: 'Swarm',
            subtitle: 'Split a task across subagents',
            onTap: () => _push(context, SwarmScreen(api: api)),
          ),
          const SizedBox(height: 12),
          _hubCard(
            context,
            icon: Icons.groups_outlined,
            title: 'Experts',
            subtitle: 'Pre-built teams of agents',
            onTap: () => _push(context, ExpertsScreen(api: api)),
          ),
          const SizedBox(height: 12),
          _hubCard(
            context,
            icon: Icons.lightbulb_outlined,
            title: 'Ideas',
            subtitle: 'Nightly-generated suggestions',
            onTap: () => _push(context, IdeasScreen(api: api)),
          ),
          const _HubSection('Runtime'),
          _hubCard(
            context,
            icon: Icons.person_outline_rounded,
            title: 'Profiles',
            subtitle: 'Agent identities',
            onTap: () => _push(context, ProfilesScreen(api: api)),
          ),
          const SizedBox(height: 12),
          _hubCard(
            context,
            icon: Icons.smart_toy_outlined,
            title: 'Models',
            subtitle: 'Default and auxiliary models',
            onTap: () => _push(context, ModelsScreen(api: api)),
          ),
          const SizedBox(height: 12),
          _hubCard(
            context,
            icon: Icons.psychology_outlined,
            title: 'Memory',
            subtitle: 'Long-term memory browser',
            onTap: () => _push(context, MemoryScreen(api: api)),
          ),
          const SizedBox(height: 12),
          _hubCard(
            context,
            icon: Icons.extension_outlined,
            title: 'Skills',
            subtitle: 'Install, toggle, import',
            onTap: () => _push(context, SkillsScreen(api: api)),
          ),
          const SizedBox(height: 12),
          _hubCard(
            context,
            icon: Icons.widgets_outlined,
            title: 'Plugins',
            subtitle: 'Tool plugins and hooks',
            onTap: () => _push(context, PluginsScreen(api: api)),
          ),
          const SizedBox(height: 12),
          _hubCard(
            context,
            icon: Icons.cable_outlined,
            title: 'Tools & MCP',
            subtitle: 'MCP servers, health, reload',
            onTap: () => _push(context, McpScreen(api: api)),
          ),
          const SizedBox(height: 12),
          _hubCard(
            context,
            icon: Icons.web_asset_outlined,
            title: 'Browser',
            subtitle: 'Live session stream and take-control',
            onTap: () => _push(context, BrowserScreen(api: api)),
          ),
          const SizedBox(height: 12),
          _hubCard(
            context,
            icon: Icons.mic_outlined,
            title: 'Voice',
            subtitle: 'Live mode, STT and TTS providers',
            onTap: () => _push(context, VoiceSettingsScreen(api: api)),
          ),
          const _HubSection('System'),
          _hubCard(
            context,
            icon: Icons.tune_rounded,
            title: 'Configs',
            subtitle: 'config.toml editor and schema',
            onTap: () => _push(context, ConfigScreen(api: api)),
          ),
          const SizedBox(height: 12),
          _hubCard(
            context,
            icon: Icons.key_outlined,
            title: 'Keys',
            subtitle: '.env API key manager',
            onTap: () => _push(context, KeysScreen(api: api)),
          ),
          const SizedBox(height: 12),
          _hubCard(
            context,
            icon: Icons.web_outlined,
            title: 'Website logins',
            subtitle: 'Browser sign-in credentials',
            onTap: () => _push(context, LoginsScreen(api: api)),
          ),
          const SizedBox(height: 12),
          _hubCard(
            context,
            icon: Icons.terminal_rounded,
            title: 'Logs',
            subtitle: 'Agent, errors, gateway tails',
            onTap: () => _push(context, LogsScreen(api: api)),
          ),
          const _HubSection('App'),
          _hubCard(
            context,
            icon: Icons.palette_outlined,
            title: 'Appearance',
            subtitle: 'Theme, text size, density',
            onTap: () => _push(context, const AppearanceScreen()),
          ),
          const SizedBox(height: 12),
          _hubCard(
            context,
            icon: Icons.notifications_outlined,
            title: 'Notifications',
            subtitle: 'Run and schedule alerts',
            onTap: () => _push(context, NotificationsScreen(api: api)),
          ),
          const SizedBox(height: 12),          _hubCard(
            context,
            icon: Icons.settings_outlined,
            title: 'Settings',
            subtitle: 'Connection, sign out, about',
            onTap: () => _push(
              context,
              SettingsScreen(
                api: api,
                settings: settings,
                onSignOut: onSignOut,
                onReconnect: onReconnect,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  Widget _hubCard(BuildContext context,
      {required IconData icon,
      required String title,
      required String subtitle,
      required VoidCallback onTap,
      Widget? trailing}) {
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
              if (trailing != null) ...[
                trailing,
                const SizedBox(width: 8),
              ],
               Icon(Icons.chevron_right_rounded,
                  color: P.inkFaint, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

/// Section header inside the More hub.
class _HubSection extends StatelessWidget {
  final String text;

  const _HubSection(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Text(text.toUpperCase(), style: PT.overline),
    );
  }
}
