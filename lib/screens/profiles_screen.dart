import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../models/models.dart';
import '../services/pantheon_api.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/chips.dart';
import '../widgets/forms.dart';
import '../widgets/pantheon_card.dart';
import '../widgets/states.dart';

/// Agent profiles: the `[agents]` table of the runtime config.
///
/// Circular avatars (six bundled presets or a custom upload), profile
/// switching, and profile creation — all through `PUT /api/config`.
class ProfilesScreen extends StatefulWidget {
  final PantheonApi api;

  const ProfilesScreen({super.key, required this.api});

  @override
  State<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends State<ProfilesScreen> {
  Future<ConfigDoc>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() => _future = widget.api.getConfig());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profiles'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded,
                color: P.accent, weight: 1.6),
            tooltip: 'New profile',
            onPressed: () async {
              final names = (await _future)?.agents.keys.toSet() ?? {};
              final created = await showPSheet<bool>(
                context,
                _CreateProfileSheet(api: widget.api, existing: names),
              );
              if (created == true && mounted) _load();
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded,
                color: P.inkSecondary, weight: 1.6),
            onPressed: _load,
          ),
        ],
      ),
      body: FutureBuilder<ConfigDoc>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return _skeleton();
          }
          if (snap.hasError) {
            return EmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'Couldn\'t load config',
              body: snap.error.toString(),
              ctaLabel: 'Retry',
              onCta: _load,
            );
          }
          final doc = snap.data!;
          final agents = doc.agents;
          final active = doc.activeAgent;
          if (agents.isEmpty) {
            return EmptyState(
              icon: Icons.person_outline_rounded,
              title: 'No profiles declared',
              body:
                  'This install has no [agents] table in its config yet. '
                  'Tap + to create the first profile.',
              ctaLabel: 'New profile',
              onCta: () async {
                final created = await showPSheet<bool>(
                  context,
                  _CreateProfileSheet(api: widget.api, existing: {}),
                );
                if (created == true && mounted) _load();
              },
            );
          }
          final names = agents.keys.toList()..sort();
          return RefreshIndicator(
            onRefresh: () async => _load(),
            color: P.accent,
            backgroundColor: P.surface,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              itemCount: names.length,
              itemBuilder: (context, i) {
                final name = names[i];
                return StaggerItem(
                    index: i,
                    child: _profileCard(
                        name, agents[name] ?? {}, active == name));
              },
            ),
          );
        },
      ),
    );
  }

  Widget _profileCard(String name, Map<String, dynamic> p, bool isActive) {
    final display = p['display_name'] as String?;
    final inherits = p['inherits'] as String?;
    final policy = p['policy'] as String?;
    final model = p['model'] as String?;
    final memoryNs = p['memory_namespace'] as String?;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PCard(
        onTap: () => _detail(name, p, isActive),
        child: Row(
          children: [
            ProfilePicture(
              avatar: p['avatar'] as String?,
              name: name,
              size: 48,
              active: isActive,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                            display?.isNotEmpty == true ? display! : name,
                            style: PT.rowTitle,
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (isActive) ...[
                        const SizedBox(width: 8),
                        const PillChip(label: 'Active', selected: true),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      if (policy != null) 'policy · $policy',
                      if (model != null) 'model · $model',
                      if (inherits != null) 'inherits · $inherits',
                    ].join('   ').ifEmpty('agent profile'),
                    style: PT.meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (memoryNs != null) ...[
                    const SizedBox(height: 2),
                    Text('memory · $memoryNs',
                        style: PT.monoSm.copyWith(fontSize: 10)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _detail(
      String name, Map<String, dynamic> p, bool isActive) async {
    final changed = await showPSheet<bool>(
      context,
      _ProfileDetailSheet(
        api: widget.api,
        name: name,
        profile: p,
        active: isActive,
        onChanged: _load,
      ),
    );
    if (changed == true && mounted) _load();
  }

  Widget _skeleton() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: 4,
      itemBuilder: (_, __) => const Padding(
        padding: EdgeInsets.only(bottom: 10),
        child: Shimmer(width: double.infinity, height: 76, radius: 16),
      ),
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

/// Circular agent avatar.
///
/// `avatar` is `preset:avatar-N` (1–6) for the bundled set, an absolute
/// file path for a custom upload, or null — which falls back to the
/// gradient-initial circle. An unresolvable value (unknown preset, missing
/// file) also falls back instead of crashing.
class ProfilePicture extends StatelessWidget {
  final String? avatar;
  final String name;
  final double size;
  final bool active;

  const ProfilePicture({
    super.key,
    required this.avatar,
    required this.name,
    this.size = 48,
    this.active = false,
  });

  /// Bundled asset for `preset:avatar-N`; null for anything else.
  static String? presetAsset(String? avatar) {
    if (avatar == null || !avatar.startsWith('preset:')) return null;
    final preset = avatar.substring('preset:'.length);
    return RegExp(r'^avatar-[1-6]$').hasMatch(preset)
        ? 'assets/avatars/$preset.jpg'
        : null;
  }

  static final Map<String, Future<bool>> _existsCache = {};

  static Future<bool> _fileExists(String path) => _existsCache
      .putIfAbsent(path, () async => await File(path).exists());

  Widget _fallback() {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        gradient: P.gradient,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        name.isEmpty ? '?' : name[0].toUpperCase(),
        style: TextStyle(
            fontFamily: PT.displayFamily,
            fontSize: size * 0.42,
            fontWeight: FontWeight.w600,
            color: Colors.white),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final asset = presetAsset(avatar);
    Widget face;
    if (asset != null) {
      face = CircleAvatar(
          radius: size / 2, backgroundImage: AssetImage(asset));
    } else if (avatar != null && avatar!.startsWith('/')) {
      face = FutureBuilder<bool>(
        future: _fileExists(avatar!),
        builder: (_, snap) {
          if (snap.data == true) {
            return CircleAvatar(
                radius: size / 2,
                backgroundImage: FileImage(File(avatar!)));
          }
          return _fallback();
        },
      );
    } else {
      face = _fallback();
    }
    if (!active) return face;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        face,
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: P.ok,
              shape: BoxShape.circle,
              border: Border.all(color: P.surface, width: 2),
            ),
            child: const Icon(Icons.check_rounded,
                size: 11, color: Colors.white, weight: 2.4),
          ),
        ),
      ],
    );
  }
}

/// Detail sheet for one profile: avatar change, fields, and (when not
/// already active) the "set as active" switch.
class _ProfileDetailSheet extends StatefulWidget {
  final PantheonApi api;
  final String name;
  final Map<String, dynamic> profile;
  final bool active;

  /// Called after an in-sheet change (e.g. a new picture) so the list
  /// behind the sheet refreshes even if the sheet is dismissed by swipe.
  final VoidCallback onChanged;

  const _ProfileDetailSheet({
    required this.api,
    required this.name,
    required this.profile,
    required this.active,
    required this.onChanged,
  });

  @override
  State<_ProfileDetailSheet> createState() => _ProfileDetailSheetState();
}

class _ProfileDetailSheetState extends State<_ProfileDetailSheet> {
  late String? _avatar;
  late final TextEditingController _userFile;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _avatar = widget.profile['avatar'] as String?;
    _userFile = TextEditingController(
        text: widget.profile['user_file']?.toString() ?? '');
  }

  @override
  void dispose() {
    _userFile.dispose();
    super.dispose();
  }

  Future<void> _changePicture() async {
    final picked =
        await showPSheet<String>(context, _AvatarPicker(current: _avatar));
    if (picked == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.api.putConfig({'agents.${widget.name}.avatar': picked});
      setState(() => _avatar = picked);
      widget.onChanged();
    } catch (e) {
      if (mounted) toastError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveUserFile() async {
    setState(() => _busy = true);
    try {
      await widget.api
          .putConfig({'agents.${widget.name}.user_file': _userFile.text.trim()});
      widget.onChanged();
      if (mounted) toast(context, 'User file saved');
    } catch (e) {
      if (mounted) toastError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setActive() async {
    setState(() => _busy = true);
    try {
      await widget.api.putConfig({'agent': widget.name});
      if (!mounted) return;
      toast(context, '${widget.name} is now the active profile');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        toastError(context, e);
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SheetHandle(),
            const SizedBox(height: 12),
            Row(
              children: [
                ProfilePicture(
                    avatar: _avatar,
                    name: widget.name,
                    size: 64,
                    active: widget.active),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.name, style: PT.sectionTitle),
                      const SizedBox(height: 4),
                      const Text('AGENT PROFILE', style: PT.overline),
                    ],
                  ),
                ),
                if (widget.active)
                  const PillChip(label: 'Active', selected: true),
              ],
            ),
            const SizedBox(height: 16),
            KvRow('display name', p['display_name']?.toString() ?? '—'),
            KvRow('inherits', p['inherits']?.toString() ?? '—'),
            KvRow('policy', p['policy']?.toString() ?? '—'),
            KvRow('model', p['model']?.toString() ?? 'runtime default'),
            KvRow('provider', p['provider']?.toString() ?? 'runtime default'),
            KvRow('memory namespace', p['memory_namespace']?.toString() ?? '—',
                mono: true),
            KvRow('persona file', p['soul_file']?.toString() ?? '—',
                mono: true),
            KvRow('instructions file', p['agents_file']?.toString() ?? '—',
                mono: true),
            KvRow('picture', _avatar ?? '—', mono: true),
            const SizedBox(height: 12),
            Text('User file', style: PT.meta),
            const SizedBox(height: 6),
            TextField(
              controller: _userFile,
              style: PT.body.copyWith(fontSize: 14),
              decoration: const InputDecoration(
                hintText: 'path to USER.md equivalent',
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(height: 8),
            TonalButton(
              label: _busy ? 'Working…' : 'Save user file',
              onTap: _busy ? null : _saveUserFile,
            ),
            const SizedBox(height: 16),
            TonalButton(
              label: _busy ? 'Working…' : 'Change picture',
              onTap: _busy ? null : _changePicture,
            ),
            const SizedBox(height: 16),
            Text('Persona files', style: PT.meta),
            const SizedBox(height: 4),
            Text(
              'Injected into the agent\'s prompt every turn. Edit with care.',
              style: PT.meta.copyWith(color: P.inkFaint, fontSize: 11),
            ),
            const SizedBox(height: 8),
            _PersonaFileCard(
              api: widget.api,
              profileName: widget.name,
              file: 'soul',
              title: 'SOUL',
              subtitle: 'Persona — who this agent is',
              onSaved: widget.onChanged,
            ),
            const SizedBox(height: 8),
            _PersonaFileCard(
              api: widget.api,
              profileName: widget.name,
              file: 'user',
              title: 'USER',
              subtitle: 'User context — who it serves',
              onSaved: widget.onChanged,
            ),
            const SizedBox(height: 8),
            _PersonaFileCard(
              api: widget.api,
              profileName: widget.name,
              file: 'agents',
              title: 'AGENTS',
              subtitle: 'Instructions — how it works',
              onSaved: widget.onChanged,
            ),
            const SizedBox(height: 12),
            if (!widget.active) ...[
              GradientButton(
                label: _busy ? 'Working…' : 'Set as active',
                onTap: _busy ? null : _setActive,
              ),
              const SizedBox(height: 12),
              Text(
                'Applies to new sessions and runs. Turns already in '
                'flight keep their current profile.',
                style: PT.meta.copyWith(color: P.inkFaint),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Avatar picker: the six bundled presets in a circular grid, plus a
/// custom-upload tile. Returns the `avatar` config value on pick.
class _AvatarPicker extends StatefulWidget {
  final String? current;

  const _AvatarPicker({required this.current});

  @override
  State<_AvatarPicker> createState() => _AvatarPickerState();
}

class _AvatarPickerState extends State<_AvatarPicker> {
  bool _picking = false;

  Future<void> _uploadCustom() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final file =
          await ImagePicker().pickImage(source: ImageSource.gallery);
      if (file == null) return;
      // ImagePicker hands back a temp/cache path the OS can purge, so
      // copy the image into our own documents directory and persist
      // THAT path instead.
      final dir = await getApplicationDocumentsDirectory();
      final avatars = Directory('${dir.path}/profile-avatars');
      await avatars.create(recursive: true);
      final ext =
          file.name.contains('.') ? '.${file.name.split('.').last}' : '.jpg';
      final target =
          File('${avatars.path}/avatar-${DateTime.now().millisecondsSinceEpoch}$ext');
      await File(file.path).copy(target.path);
      if (mounted) Navigator.pop(context, target.path);
    } catch (e) {
      if (mounted) toastError(context, e);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SheetHandle(),
            const SizedBox(height: 12),
            Text('Choose a picture', style: PT.sectionTitle),
            const SizedBox(height: 4),
            const Text('PROFILE PICTURE', style: PT.overline),
            const SizedBox(height: 16),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
              ),
              itemCount: 7,
              itemBuilder: (context, i) {
                if (i < 6) {
                  final value = 'preset:avatar-${i + 1}';
                  final selected = widget.current == value;
                  return GestureDetector(
                    onTap: () => Navigator.pop(context, value),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected ? P.accent : Colors.transparent,
                          width: 3,
                        ),
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          'assets/avatars/avatar-${i + 1}.jpg',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  );
                }
                return GestureDetector(
                  onTap: _uploadCustom,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: P.tonal,
                      border: Border.all(color: P.borderStrong, width: 1),
                    ),
                    child: _picking
                        ? const Center(
                            child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2)))
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.upload_rounded,
                                  color: P.inkSecondary, size: 26),
                              const SizedBox(height: 4),
                              Text('Upload',
                                  style: PT.meta
                                      .copyWith(color: P.inkSecondary)),
                            ],
                          ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            Text(
              'Custom uploads are copied into the app\'s storage and kept '
              'as an absolute path on the profile.',
              style: PT.meta.copyWith(color: P.inkFaint),
            ),
          ],
        ),
      ),
    );
  }
}

/// Create-profile form. Writes the new `[agents.<name>]` table through
/// dotted-path `PUT /api/config` changes.
class _CreateProfileSheet extends StatefulWidget {
  final PantheonApi api;
  final Set<String> existing;

  const _CreateProfileSheet({required this.api, required this.existing});

  @override
  State<_CreateProfileSheet> createState() => _CreateProfileSheetState();
}

class _CreateProfileSheetState extends State<_CreateProfileSheet> {
  final _name = TextEditingController();
  final _display = TextEditingController();
  final _model = TextEditingController();
  final _provider = TextEditingController();
  final _namespace = TextEditingController();
  final _soul = TextEditingController();
  final _agentsFile = TextEditingController();
  final _userFile = TextEditingController();
  String? _inherits;
  String? _policy;
  String? _avatar;
  bool _saving = false;

  static final _slug = RegExp(r'^[a-z0-9][a-z0-9_-]*$');

  @override
  void initState() {
    super.initState();
    // Keep the avatar-preview initial in sync with the typed name.
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _display.dispose();
    _model.dispose();
    _provider.dispose();
    _namespace.dispose();
    _soul.dispose();
    _agentsFile.dispose();
    _userFile.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final picked =
        await showPSheet<String>(context, _AvatarPicker(current: _avatar));
    if (picked != null) setState(() => _avatar = picked);
  }

  Future<void> _save() async {
    final name = _name.text.trim().toLowerCase();
    if (name.isEmpty) {
      toast(context, 'Give the profile a name first');
      return;
    }
    if (!_slug.hasMatch(name)) {
      toast(context,
          'Name must be a slug: lowercase letters, digits, - and _');
      return;
    }
    if (widget.existing.contains(name)) {
      toast(context, 'A profile named "$name" already exists');
      return;
    }
    setState(() => _saving = true);
    try {
      final prefix = 'agents.$name';
      final changes = <String, dynamic>{
        // Always send display_name so the table is created even when
        // every other field is left blank.
        '$prefix.display_name':
            _display.text.trim().ifEmpty(name),
      };
      void put(String key, String value) {
        final v = value.trim();
        if (v.isNotEmpty) changes['$prefix.$key'] = v;
      }

      put('inherits', _inherits ?? '');
      put('policy', _policy ?? '');
      put('model', _model.text);
      put('provider', _provider.text);
      put('memory_namespace', _namespace.text);
      put('soul_file', _soul.text);
      put('agents_file', _agentsFile.text);
      put('user_file', _userFile.text);
      if (_avatar != null) changes['$prefix.avatar'] = _avatar;
      await widget.api.putConfig(changes);
      if (!mounted) return;
      toast(context, 'Profile "$name" created');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        toastError(context, e);
        setState(() => _saving = false);
      }
    }
  }

  Widget _field(TextEditingController c, String label, String hint,
      {TextInputType? keyboard}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        style: PT.body,
        keyboardType: keyboard,
        decoration:
            InputDecoration(labelText: label, hintText: hint),
      ),
    );
  }

  Widget _dropdown(String label, String? value, List<String> options,
      ValueChanged<String?> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: PT.meta),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: value,
            items: options
                .map((o) => DropdownMenuItem(
                    value: o.isEmpty ? null : o,
                    child: Text(o.isEmpty ? '—' : o)))
                .toList(),
            onChanged: onChanged,
            style: PT.body.copyWith(fontSize: 14),
            dropdownColor: P.surface,
            decoration: const InputDecoration(
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inheritsOptions = <String>['', ...widget.existing.toList()..sort()];
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            20, 8, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SheetHandle(),
            const SizedBox(height: 12),
            Text('New profile', style: PT.sectionTitle),
            const SizedBox(height: 4),
            const Text('AGENT PROFILE', style: PT.overline),
            const SizedBox(height: 16),
            Row(
              children: [
                GestureDetector(
                  onTap: _pickAvatar,
                  child: ProfilePicture(
                      avatar: _avatar, name: _name.text, size: 64),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _avatar == null
                        ? 'Tap the circle to pick a picture.'
                        : 'Picture selected — tap to change.',
                    style: PT.meta.copyWith(color: P.inkFaint),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _field(_name, 'Name', 'e.g. nyx — the [agents.<name>] key'),
            _field(_display, 'Display name', 'e.g. Nyx'),
            _dropdown('Inherits', _inherits, inheritsOptions,
                (v) => setState(() => _inherits = v)),
            _dropdown('Policy', _policy,
                const ['', 'reader', 'coder', 'coder_memory'],
                (v) => setState(() => _policy = v)),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _field(_provider, 'Provider', 'optional')),
                const SizedBox(width: 12),
                Expanded(child: _field(_model, 'Model', 'optional')),
              ],
            ),
            _field(_namespace, 'Memory namespace',
                'defaults to agent:<name>'),
            _field(_soul, 'Persona file', 'path to SOUL.md equivalent'),
            _field(_userFile, 'User file', 'path to USER.md equivalent'),
            _field(_agentsFile, 'Instructions file',
                'path to AGENTS.md equivalent'),
            const SizedBox(height: 4),
            GradientButton(
              label: _saving ? 'Creating…' : 'Create profile',
              onTap: _saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}

/// One persona-file card (SOUL / USER / AGENTS) in the profile detail
/// sheet: 2-line content preview + chevron, tap to open the full editor.
class _PersonaFileCard extends StatefulWidget {
  final PantheonApi api;
  final String profileName;
  final String file;
  final String title;
  final String subtitle;
  final VoidCallback onSaved;

  const _PersonaFileCard({
    required this.api,
    required this.profileName,
    required this.file,
    required this.title,
    required this.subtitle,
    required this.onSaved,
  });

  @override
  State<_PersonaFileCard> createState() => _PersonaFileCardState();
}

class _PersonaFileCardState extends State<_PersonaFileCard> {
  String? _preview;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final files = await widget.api.profileFiles(widget.profileName);
      final entry = files[widget.file] as Map?;
      final content = entry?['content']?.toString() ?? '';
      if (mounted) {
        setState(() {
          _preview = content;
          _failed = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _open() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _PersonaFileEditor(
          api: widget.api,
          profileName: widget.profileName,
          file: widget.file,
          title: widget.title,
        ),
      ),
    );
    if (saved == true) {
      widget.onSaved();
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return PCard(
      onTap: _open,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.title, style: PT.rowTitle),
                const SizedBox(height: 2),
                Text(widget.subtitle,
                    style: PT.meta.copyWith(color: P.inkFaint, fontSize: 11)),
                const SizedBox(height: 6),
                Text(
                  _failed
                      ? 'Could not load'
                      : preview == null
                          ? 'Loading…'
                          : preview.isEmpty
                              ? 'Empty — tap to write'
                              : preview.split('\n').take(2).join('\n'),
                  style: PT.monoSm.copyWith(
                    fontSize: 11,
                    color: preview?.isEmpty != false
                        ? P.inkFaint
                        : P.inkSecondary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right_rounded,
              color: P.inkFaint, weight: 1.6),
        ],
      ),
    );
  }
}

/// Full-screen monospace editor for one persona file, with Save/Discard.
class _PersonaFileEditor extends StatefulWidget {
  final PantheonApi api;
  final String profileName;
  final String file;
  final String title;

  const _PersonaFileEditor({
    required this.api,
    required this.profileName,
    required this.file,
    required this.title,
  });

  @override
  State<_PersonaFileEditor> createState() => _PersonaFileEditorState();
}

class _PersonaFileEditorState extends State<_PersonaFileEditor> {
  late final TextEditingController _controller;
  String _original = '';
  bool _loading = true;
  bool _saving = false;
  String? _path;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final files = await widget.api.profileFiles(widget.profileName);
      final entry = files[widget.file] as Map?;
      final content = entry?['content']?.toString() ?? '';
      if (!mounted) return;
      setState(() {
        _original = content;
        _controller.text = content;
        _path = entry?['path']?.toString();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      toastError(context, e);
    }
  }

  bool get _dirty => _controller.text != _original;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.api.saveProfileFile(
          widget.profileName, widget.file, _controller.text);
      if (!mounted) return;
      toast(context, '${widget.title} saved');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        toastError(context, e);
        setState(() => _saving = false);
      }
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: P.surface,
        title: Text('Discard changes?', style: PT.sectionTitle),
        content: Text(
          'You have unsaved changes to ${widget.title}.',
          style: PT.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Keep editing', style: TextStyle(color: P.accent)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Discard', style: TextStyle(color: Colors.red.shade300)),
          ),
        ],
      ),
    );
    return discard == true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) {
          Navigator.pop(context, false);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          actions: [
            TextButton(
              onPressed: _saving || _loading || !_dirty ? null : _save,
              child: Text(
                _saving ? 'Saving…' : 'Save',
                style: TextStyle(
                  color: _dirty && !_saving ? P.accent : P.inkFaint,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_path != null) ...[
                      Text(
                        _path!,
                        style: PT.monoSm.copyWith(
                            fontSize: 10, color: P.inkFaint),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                    ],
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        style: PT.monoSm.copyWith(fontSize: 13, height: 1.6),
                        decoration: const InputDecoration(
                          hintText: 'Write the file contents…',
                          contentPadding: EdgeInsets.all(14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
