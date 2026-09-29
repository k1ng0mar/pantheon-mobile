import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/app_preferences.dart';
import '../theme.dart';
import '../widgets/agent_avatar.dart';
import '../widgets/buttons.dart';
import '../widgets/chips.dart';
import '../widgets/forms.dart';
import '../widgets/pantheon_card.dart';

/// Appearance: theme, custom colors, typography, chat, loading indicator,
/// density, motion, and haptics.
///
/// Every control takes effect immediately app-wide (theme mode drives
/// `MaterialApp.themeMode` + the brightness-aware `P` palette, text size a
/// root `MediaQuery.textScaler`, density `visualDensity`, and the rest are
/// read at build time by the widgets they affect).
class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final prefs = AppPreferences.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Appearance')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          const Overline('Theme'),
          PCard(
            child: ValueListenableBuilder<ThemeMode>(
              valueListenable: prefs.themeMode,
              builder: (_, mode, __) => SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.system,
                    label: Text('System'),
                    icon: Icon(Icons.settings_suggest_outlined, size: 18),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    label: Text('Light'),
                    icon: Icon(Icons.light_mode_outlined, size: 18),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    label: Text('Dark'),
                    icon: Icon(Icons.dark_mode_outlined, size: 18),
                  ),
                ],
                selected: {mode},
                onSelectionChanged: (s) => prefs.setThemeMode(s.first),
                showSelectedIcon: false,
              ),
            ),
          ),
          const Overline('Custom colors'),
          PCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _HexColorField(
                    label: 'Accent',
                    notifier: prefs.customAccent,
                    onSet: prefs.setCustomAccent),
                const Divider(height: 1, indent: 14, endIndent: 14),
                _HexColorField(
                    label: 'Background',
                    notifier: prefs.customBg,
                    onSet: prefs.setCustomBg),
                const Divider(height: 1, indent: 14, endIndent: 14),
                _HexColorField(
                    label: 'Surface',
                    notifier: prefs.customSurface,
                    onSet: prefs.setCustomSurface),
                const Divider(height: 1, indent: 14, endIndent: 14),
                _HexColorField(
                    label: 'Tonal',
                    notifier: prefs.customTonal,
                    onSet: prefs.setCustomTonal),
              ],
            ),
          ),
          const SizedBox(height: 10),
          TonalButton(
              label: 'Reset custom colors',
              onTap: () => prefs.resetCustomColors()),
          const Overline('Typography'),
          PCard(
            child: ValueListenableBuilder<String>(
              valueListenable: prefs.bodyFont,
              builder: (_, font, __) => SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'Inter', label: Text('Inter')),
                  ButtonSegment(
                      value: 'SpaceGrotesk', label: Text('Space Grotesk')),
                  ButtonSegment(value: 'JetBrainsMono', label: Text('Mono')),
                ],
                selected: {font},
                onSelectionChanged: (s) => prefs.setBodyFont(s.first),
                showSelectedIcon: false,
              ),
            ),
          ),
          const SizedBox(height: 12),
          PCard(
            child: ValueListenableBuilder<double>(
              valueListenable: prefs.textScale,
              builder: (_, scale, __) => Row(
                children: [
                  Text('A', style: PT.small),
                  Expanded(
                    child: Slider(
                      value: scale,
                      min: 0.8,
                      max: 1.4,
                      divisions: 12,
                      label: '${(scale * 100).round()}%',
                      onChanged: (v) => prefs.setTextScale(
                          double.parse(v.toStringAsFixed(2))),
                    ),
                  ),
                  Text('A', style: PT.rowTitle),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 44,
                    child: Text('${(scale * 100).round()}%',
                        style: PT.monoSm, textAlign: TextAlign.right),
                  ),
                ],
              ),
            ),
          ),
          const Overline('Chat'),
          PCard(
            child: ValueListenableBuilder<String>(
              valueListenable: prefs.bubbleStyle,
              builder: (_, style, __) => SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                      value: 'rounded',
                      label: Text('Rounded'),
                      icon: Icon(Icons.chat_bubble_outline_rounded, size: 18)),
                  ButtonSegment(
                      value: 'flat',
                      label: Text('Flat'),
                      icon: Icon(Icons.crop_square_rounded, size: 18)),
                ],
                selected: {style},
                onSelectionChanged: (s) => prefs.setBubbleStyle(s.first),
                showSelectedIcon: false,
              ),
            ),
          ),
          const SizedBox(height: 12),
          PCard(
            child: ValueListenableBuilder<String>(
              valueListenable: prefs.chatDensity,
              builder: (_, density, __) => SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                      value: 'comfortable', label: Text('Comfortable')),
                  ButtonSegment(value: 'compact', label: Text('Compact')),
                ],
                selected: {density},
                onSelectionChanged: (s) => prefs.setChatDensity(s.first),
                showSelectedIcon: false,
              ),
            ),
          ),
          const SizedBox(height: 12),
          PCard(
            child: ValueListenableBuilder<String>(
              valueListenable: prefs.chatBg,
              builder: (_, bg, __) => SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'default', label: Text('Default')),
                  ButtonSegment(value: 'tinted', label: Text('Tinted')),
                  ButtonSegment(value: 'dim', label: Text('Dim')),
                ],
                selected: {bg},
                onSelectionChanged: (s) => prefs.setChatBg(s.first),
                showSelectedIcon: false,
              ),
            ),
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<bool>(
            valueListenable: prefs.showTimestamps,
            builder: (_, show, __) => PRowCard(
              rows: [
                PRow(
                  title: 'Timestamps',
                  subtitle: 'Show a time under each message',
                  dotColor: P.info,
                  onTap: () => prefs.setShowTimestamps(!show),
                  trailing: Switch(
                      value: show, onChanged: prefs.setShowTimestamps),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          PCard(
            child: ValueListenableBuilder<String>(
              valueListenable: prefs.timestampFormat,
              builder: (_, format, __) => SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                      value: 'relative', label: Text('Relative (2m ago)')),
                  ButtonSegment(
                      value: 'absolute', label: Text('Absolute (10:29pm)')),
                ],
                selected: {format},
                onSelectionChanged: (s) => prefs.setTimestampFormat(s.first),
                showSelectedIcon: false,
              ),
            ),
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<bool>(
            valueListenable: prefs.dateDividers,
            builder: (_, dividers, __) => PRowCard(
              rows: [
                PRow(
                  title: 'Date dividers',
                  subtitle: 'Day separator rows in chat',
                  dotColor: P.info,
                  onTap: () => prefs.setDateDividers(!dividers),
                  trailing: Switch(
                      value: dividers, onChanged: prefs.setDateDividers),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          PCard(
            child: ValueListenableBuilder<bool>(
              valueListenable: prefs.returnSends,
              builder: (_, send, __) => SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                      value: true,
                      label: Text('Send'),
                      icon: Icon(Icons.send_rounded, size: 18)),
                  ButtonSegment(
                      value: false,
                      label: Text('Newline'),
                      icon: Icon(Icons.keyboard_return_rounded, size: 18)),
                ],
                selected: {send},
                onSelectionChanged: (s) => prefs.setReturnSends(s.first),
                showSelectedIcon: false,
              ),
            ),
          ),
          const Overline('Agent'),
          const PCard(child: _AgentProfileRow()),
          const Overline('Code blocks'),
          PCard(
            child: ValueListenableBuilder<String>(
              valueListenable: prefs.codeTheme,
              builder: (_, theme, __) => SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'github', label: Text('GitHub')),
                  ButtonSegment(value: 'dracula', label: Text('Dracula')),
                  ButtonSegment(
                      value: 'atom-one-dark', label: Text('Atom One Dark')),
                ],
                selected: {theme},
                onSelectionChanged: (s) => prefs.setCodeTheme(s.first),
                showSelectedIcon: false,
              ),
            ),
          ),
          const Overline('Loading indicator'),
          PCard(
            child: ValueListenableBuilder<String>(
              valueListenable: prefs.loadingStyle,
              builder: (_, style, __) => SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                      value: 'spinner',
                      label: Text('Spinner'),
                      icon: Icon(Icons.refresh_rounded, size: 18)),
                  ButtonSegment(
                      value: 'dots',
                      label: Text('Dots'),
                      icon: Icon(Icons.more_horiz_rounded, size: 18)),
                  ButtonSegment(
                      value: 'pulse',
                      label: Text('Pulse'),
                      icon: Icon(Icons.circle_outlined, size: 18)),
                ],
                selected: {style},
                onSelectionChanged: (s) => prefs.setLoadingStyle(s.first),
                showSelectedIcon: false,
              ),
            ),
          ),
          const Overline('Density'),
          ValueListenableBuilder<bool>(
            valueListenable: prefs.compactDensity,
            builder: (_, compact, __) => PRowCard(
              rows: [
                PRow(
                  title: 'Comfortable',
                  subtitle: 'Roomier rows and spacing',
                  dotColor: P.ok,
                  onTap: () => prefs.setCompactDensity(false),
                  trailing: Radio<bool>(
                    value: false,
                    groupValue: compact,
                    onChanged: (_) => prefs.setCompactDensity(false),
                  ),
                ),
                PRow(
                  title: 'Compact',
                  subtitle: 'Denser rows, more on screen',
                  dotColor: P.info,
                  onTap: () => prefs.setCompactDensity(true),
                  trailing: Radio<bool>(
                    value: true,
                    groupValue: compact,
                    onChanged: (_) => prefs.setCompactDensity(true),
                  ),
                ),
              ],
            ),
          ),
          const Overline('Motion & feedback'),
          ValueListenableBuilder<bool>(
            valueListenable: prefs.reduceMotion,
            builder: (_, reduce, __) => PRowCard(
              rows: [
                PRow(
                  title: 'Reduce motion',
                  subtitle: 'Disable entrance animations and transitions',
                  dotColor: P.warn,
                  onTap: () => prefs.setReduceMotion(!reduce),
                  trailing: Switch(
                      value: reduce, onChanged: prefs.setReduceMotion),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<bool>(
            valueListenable: prefs.hapticsEnabled,
            builder: (_, haptics, __) => PRowCard(
              rows: [
                PRow(
                  title: 'Haptic feedback',
                  subtitle: 'Vibrate on send, turn complete, and errors',
                  dotColor: P.accent,
                  onTap: () => prefs.setHapticsEnabled(!haptics),
                  trailing: Switch(
                      value: haptics, onChanged: prefs.setHapticsEnabled),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Agent profile image row: circular preview, gallery pick, remove/reset.
/// The picked path persists in [AppPreferences.agentAvatarPath]; the chat
/// avatar reads it live.
class _AgentProfileRow extends StatefulWidget {
  const _AgentProfileRow();

  @override
  State<_AgentProfileRow> createState() => _AgentProfileRowState();
}

class _AgentProfileRowState extends State<_AgentProfileRow> {
  bool _picking = false;

  Future<void> _pick() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final file =
          await ImagePicker().pickImage(source: ImageSource.gallery);
      if (file != null) {
        await AppPreferences.instance.setAgentAvatarPath(file.path);
      }
    } catch (e) {
      if (mounted) toastError(context, e);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: AppPreferences.instance.agentAvatarPath,
      builder: (_, path, __) => Row(
        children: [
          const AgentAvatar(size: 46),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Profile image', style: PT.rowTitle),
                const SizedBox(height: 2),
                Text(
                  path == null ? 'Default avatar' : 'Custom image set',
                  style: PT.faint,
                ),
              ],
            ),
          ),
          if (path != null)
            TextButton(
              onPressed: () =>
                  AppPreferences.instance.setAgentAvatarPath(null),
              child: Text('Remove', style: PT.label.copyWith(color: P.warn)),
            ),
          TonalButton(
            label: _picking ? 'Picking…' : 'Choose',
            onTap: _picking ? null : _pick,
          ),
        ],
      ),
    );
  }
}

/// A hex color input row: label, preview swatch, #RRGGBB field, clear.
/// Empty input (or the X) clears back to the palette default.
class _HexColorField extends StatefulWidget {
  final String label;
  final ValueNotifier<Color?> notifier;
  final Future<void> Function(Color?) onSet;

  const _HexColorField(
      {required this.label, required this.notifier, required this.onSet});

  @override
  State<_HexColorField> createState() => _HexColorFieldState();
}

class _HexColorFieldState extends State<_HexColorField> {
  late final TextEditingController _ctrl;
  String? _error;

  static String _hexOf(Color? c) {
    if (c == null) return '';
    final v = c.value.toRadixString(16).padLeft(8, '0').toUpperCase();
    return '#${c.alpha == 0xFF ? v.substring(2) : v}';
  }

  static Color? _parse(String s) {
    var h = s.trim().replaceAll('#', '');
    if (h.length == 6) h = 'FF$h';
    if (h.length != 8) return null;
    final v = int.tryParse(h, radix: 16);
    return v == null ? null : Color(v);
  }

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _hexOf(widget.notifier.value));
    widget.notifier.addListener(_sync);
  }

  void _sync() {
    final hex = _hexOf(widget.notifier.value);
    if (_ctrl.text != hex) _ctrl.text = hex;
  }

  @override
  void dispose() {
    widget.notifier.removeListener(_sync);
    _ctrl.dispose();
    super.dispose();
  }

  void _apply() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) {
      setState(() => _error = null);
      widget.onSet(null);
      return;
    }
    final c = _parse(text);
    if (c == null) {
      setState(() => _error = '#RRGGBB');
      return;
    }
    setState(() => _error = null);
    widget.onSet(c);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color?>(
      valueListenable: widget.notifier,
      builder: (_, color, __) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color ?? P.tonal,
                border: Border.all(color: P.borderStrong),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(widget.label, style: PT.rowTitle)),
            SizedBox(
              width: 104,
              child: TextField(
                controller: _ctrl,
                style: PT.mono,
                decoration: InputDecoration(
                  hintText: '#8B5CFF',
                  errorText: _error,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                ),
                onSubmitted: (_) => _apply(),
              ),
            ),
            if (color != null)
              IconButton(
                icon: const Icon(Icons.clear_rounded, size: 18),
                color: P.inkFaint,
                onPressed: () {
                  _ctrl.clear();
                  setState(() => _error = null);
                  widget.onSet(null);
                },
              ),
          ],
        ),
      ),
    );
  }
}
