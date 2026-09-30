import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/models.dart';
import '../services/pantheon_api.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/chips.dart';
import '../widgets/forms.dart';
import '../widgets/states.dart';

/// Configs: view the raw config.toml, edit it (validated server-side),
/// and browse the flattened schema as a reference.
class ConfigScreen extends StatefulWidget {
  final PantheonApi api;

  const ConfigScreen({super.key, required this.api});

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  int _tab = 0; // 0 = config, 1 = schema
  Future<ConfigDoc>? _docFuture;
  Future<List<ConfigField>>? _schemaFuture;
  final _editor = TextEditingController();
  bool _editing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _editor.dispose();
    super.dispose();
  }

  void _load() {
    setState(() {
      _docFuture = widget.api.getConfig().then((d) {
        if (!_editing) _editor.text = d.raw;
        return d;
      });
      _schemaFuture = widget.api.configSchema();
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.api.importConfig(_editor.text);
      if (!mounted) return;
      toast(context, 'Config saved.');
      setState(() => _editing = false);
      _load();
    } catch (e) {
      if (mounted) toastError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configs'),
        actions: [
          if (_tab == 0 && !_editing)
            IconButton(
              tooltip: 'Copy',
              icon:  Icon(Icons.copy_rounded,
                  color: P.inkSecondary, weight: 1.6),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _editor.text));
                toast(context, 'Config copied.');
              },
            ),
          IconButton(
            icon:  Icon(Icons.refresh_rounded,
                color: P.inkSecondary, weight: 1.6),
            onPressed: _load,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: SegTab(
                      label: 'config.toml',
                      selected: _tab == 0,
                      onTap: () => setState(() => _tab = 0)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SegTab(
                      label: 'Schema',
                      selected: _tab == 1,
                      onTap: () => setState(() => _tab = 1)),
                ),
              ],
            ),
          ),
          Expanded(child: _tab == 0 ? _configTab() : _schemaTab()),
        ],
      ),
    );
  }

  Widget _configTab() {
    return FutureBuilder<ConfigDoc>(
      future: _docFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting &&
            _editor.text.isEmpty) {
          return  Center(
              child: CircularProgressIndicator(color: P.accent));
        }
        if (snap.hasError && _editor.text.isEmpty) {
          return EmptyState(
            icon: Icons.cloud_off_outlined,
            title: 'Couldn\'t load config',
            body: snap.error.toString(),
            ctaLabel: 'Retry',
            onCta: _load,
          );
        }
        return Column(
          children: [
            if (snap.data != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(snap.data!.path,
                          style: PT.monoSm,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Container(
                  decoration: BoxDecoration(
                    color: P.surface,
                    borderRadius: BorderRadius.circular(P.r16),
                    border: Border.all(color: P.border),
                  ),
                  child: _editing
                      ? TextField(
                          controller: _editor,
                          expands: true,
                          maxLines: null,
                          style: PT.mono
                              .copyWith(fontSize: 12, color: P.ink),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.all(14),
                            filled: false,
                          ),
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.all(14),
                          child: SelectableText(
                            _editor.text,
                            style: PT.mono
                                .copyWith(fontSize: 12, color: P.inkSecondary),
                          ),
                        ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _editing
                  ? Row(
                      children: [
                        Expanded(
                          child: TonalButton(
                            label: 'Cancel',
                            onTap: _saving
                                ? null
                                : () => setState(() {
                                      _editing = false;
                                      _editor.text =
                                          snap.data?.raw ?? _editor.text;
                                    }),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: GradientButton(
                            label: _saving ? 'Saving…' : 'Save',
                            onTap: _saving ? null : _save,
                          ),
                        ),
                      ],
                    )
                  : SizedBox(
                      width: double.infinity,
                      child: GradientButton(
                        label: 'Edit config',
                        icon: Icons.edit_rounded,
                        onTap: () => setState(() => _editing = true),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _schemaTab() {
    return FutureBuilder<List<ConfigField>>(
      future: _schemaFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return _skeleton();
        }
        if (snap.hasError) {
          return EmptyState(
            icon: Icons.cloud_off_outlined,
            title: 'Couldn\'t load schema',
            body: snap.error.toString(),
            ctaLabel: 'Retry',
            onCta: _load,
          );
        }
        final fields = snap.data!;
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: fields.length,
          itemBuilder: (context, i) {
            final f = fields[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(f.path,
                      style: PT.mono.copyWith(fontSize: 12, color: P.ink)),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      PillChip(label: f.type, selected: false),
                      if (f.enumValues != null) ...[
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(f.enumValues!.join(' | '),
                              style: PT.faint,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _skeleton() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: 10,
      itemBuilder: (_, __) => const Padding(
        padding: EdgeInsets.only(bottom: 8),
        child: Shimmer(width: double.infinity, height: 34, radius: 8),
      ),
    );
  }
}
