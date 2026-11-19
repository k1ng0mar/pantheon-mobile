import 'package:flutter/material.dart';

import '../theme.dart';
import 'states.dart';

/// One import request from the skill import sheet. [source] selects how
/// the value is sent to `POST /api/skills/import`: a GitHub repo goes as
/// `{repo, subpath?}`, everything else as a `{url}` (registry schemes
/// carry their prefix).
class SkillImportRequest {
  final String source; // repo | clawhub | hermes | url
  final String value;
  final String? subpath;

  const SkillImportRequest({
    required this.source,
    required this.value,
    this.subpath,
  });

  bool get isRepo => source == 'repo';

  /// The `url` payload for non-repo sources.
  String get url => switch (source) {
        'clawhub' => 'clawhub:$value',
        'hermes' => 'hermes:$value',
        _ => value,
      };

  String get confirmBody => switch (source) {
        'repo' =>
          'Pantheon will clone $value and install every SKILL.md it finds.',
        'clawhub' =>
          'Pantheon will fetch the ClawHub bundle for "$value" and install it.',
        'hermes' =>
          'Pantheon will fetch the Hermes skill at "$value" and install it.',
        _ => 'Pantheon will fetch $value and install the SKILL.md.',
      };
}

/// The sources a skill can come from. The runtime already resolves each
/// of these server-side; the sheet just collects the right input.
const _sources = <({String id, String label, String field, String hint})>[
  (
    id: 'repo',
    label: 'GitHub',
    field: 'Repo URL',
    hint: 'https://github.com/owner/repo',
  ),
  (
    id: 'clawhub',
    label: 'ClawHub',
    field: 'Slug',
    hint: 'skill-name or owner/skill-name',
  ),
  (
    id: 'hermes',
    label: 'Hermes',
    field: 'Skill path',
    hint: 'skills/category/name',
  ),
  (
    id: 'url',
    label: 'URL',
    field: 'SKILL.md URL',
    hint: 'https://…/SKILL.md',
  ),
];

/// Bottom sheet that collects a skill import from any supported source.
/// Returns null on cancel.
Future<SkillImportRequest?> showSkillImportSheet(BuildContext context) {
  return showPSheet<SkillImportRequest>(context, const _SkillImportSheet());
}

class _SkillImportSheet extends StatefulWidget {
  const _SkillImportSheet();

  @override
  State<_SkillImportSheet> createState() => _SkillImportSheetState();
}

class _SkillImportSheetState extends State<_SkillImportSheet> {
  String _source = 'repo';
  final _value = TextEditingController();
  final _subpath = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _value.dispose();
    _subpath.dispose();
    super.dispose();
  }

  ({String id, String label, String field, String hint}) get _spec =>
      _sources.firstWhere((s) => s.id == _source);

  void _submit() {
    final v = _value.text.trim();
    if (v.isEmpty) {
      setState(() => _error = 'Enter a ${_spec.field.toLowerCase()} first.');
      return;
    }
    Navigator.of(context).pop(SkillImportRequest(
      source: _source,
      value: v,
      subpath: _source == 'repo' ? _subpath.text.trim() : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final spec = _spec;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetHandle(),
            const SizedBox(height: 12),
            Text('Import skill', style: PT.sectionTitle),
            const SizedBox(height: 4),
            Text('From a marketplace, a repo, or a direct link.',
                style: PT.small),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in _sources)
                  GestureDetector(
                    onTap: () => setState(() {
                      _source = s.id;
                      _error = null;
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: _source == s.id ? P.accent : P.tonal,
                        border: Border.all(
                            color: _source == s.id ? P.accent : P.border),
                      ),
                      child: Text(
                        s.label,
                        style: PT.small.copyWith(
                          color:
                              _source == s.id ? Colors.white : P.inkSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _value,
              autofocus: true,
              keyboardType: _source == 'url' || _source == 'repo'
                  ? TextInputType.url
                  : TextInputType.text,
              style: PT.body.copyWith(fontSize: 14),
              decoration: InputDecoration(
                labelText: spec.field,
                hintText: spec.hint,
                errorText: _error,
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _submit(),
            ),
            if (_source == 'repo') ...[
              const SizedBox(height: 12),
              TextField(
                controller: _subpath,
                style: PT.body.copyWith(fontSize: 14),
                decoration: const InputDecoration(
                  labelText: 'Subpath (optional)',
                  hintText: 'skills/my-skill',
                ),
              ),
            ],
            const SizedBox(height: 20),
            GestureDetector(
              onTap: _submit,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  gradient: P.gradient,
                  borderRadius: BorderRadius.circular(999),
                ),
                alignment: Alignment.center,
                child: Text('Import',
                    style: PT.label.copyWith(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
