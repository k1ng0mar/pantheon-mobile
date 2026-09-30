import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/pantheon_api.dart';
import '../theme.dart';
import '../widgets/buttons.dart';
import '../widgets/forms.dart';
import '../widgets/pantheon_card.dart';
import '../widgets/states.dart';

/// A speech backend: registry id, display label, the env var holding its
/// API key (null = keyless/local), and whether it's the recommended pick.
typedef VoiceBackend = ({String id, String label, String? keyEnv, bool recommended});

const List<VoiceBackend> _sttBackends = [
  (id: 'groq', label: 'Groq Whisper', keyEnv: 'GROQ_API_KEY', recommended: true),
  (id: 'openai', label: 'OpenAI', keyEnv: 'OPENAI_API_KEY', recommended: false),
  (id: 'mistral', label: 'Mistral', keyEnv: 'MISTRAL_API_KEY', recommended: false),
  (id: 'deepgram', label: 'Deepgram', keyEnv: 'DEEPGRAM_API_KEY', recommended: false),
  (
    id: 'elevenlabs',
    label: 'ElevenLabs Scribe',
    keyEnv: 'ELEVENLABS_API_KEY',
    recommended: false
  ),
  (id: 'xai', label: 'xAI Grok', keyEnv: 'XAI_API_KEY', recommended: false),
  (
    id: 'assemblyai',
    label: 'AssemblyAI',
    keyEnv: 'ASSEMBLYAI_API_KEY',
    recommended: false
  ),
  (id: 'command', label: 'Custom command', keyEnv: null, recommended: false),
];

const List<VoiceBackend> _ttsBackends = [
  (id: 'piper-local', label: 'Piper (on-device)', keyEnv: null, recommended: true),
  (id: 'kokoro-local', label: 'Kokoro (on-device)', keyEnv: null, recommended: false),
  (id: 'openai', label: 'OpenAI', keyEnv: 'OPENAI_API_KEY', recommended: false),
  (
    id: 'elevenlabs',
    label: 'ElevenLabs',
    keyEnv: 'ELEVENLABS_API_KEY',
    recommended: false
  ),
  (id: 'deepgram', label: 'Deepgram', keyEnv: 'DEEPGRAM_API_KEY', recommended: false),
  (id: 'gemini', label: 'Gemini', keyEnv: 'GEMINI_API_KEY', recommended: false),
  (id: 'fishaudio', label: 'Fish Audio', keyEnv: 'FISH_API_KEY', recommended: false),
  (
    id: 'fishspeech-local',
    label: 'Fish Speech (on-device)',
    keyEnv: null,
    recommended: false
  ),
  (id: 'command', label: 'Custom command', keyEnv: null, recommended: false),
];

/// Voice settings: the `[voice]` live-mode knobs plus the `[stt]` / `[tts]`
/// provider selection. There is no dedicated voice REST surface — this
/// page reads and writes the shared config document (`PUT /api/config`).
class VoiceSettingsScreen extends StatefulWidget {
  final PantheonApi api;

  const VoiceSettingsScreen({super.key, required this.api});

  @override
  State<VoiceSettingsScreen> createState() => _VoiceSettingsScreenState();
}

class _VoiceSettingsScreenState extends State<VoiceSettingsScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;

  bool _liveEnabled = false;
  String? _sttBackend;
  String? _ttsBackend;
  final _sttModel = TextEditingController();
  final _ttsVoice = TextEditingController();
  final _maxSession = TextEditingController();
  final _maxUtterance = TextEditingController();
  final _silenceMs = TextEditingController();

  @override
  void dispose() {
    _sttModel.dispose();
    _ttsVoice.dispose();
    _maxSession.dispose();
    _maxUtterance.dispose();
    _silenceMs.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Map<String, dynamic> _section(Map<String, dynamic> values, String name) {
    final s = values[name];
    return s is Map ? s.cast<String, dynamic>() : <String, dynamic>{};
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final doc = await widget.api.getConfig();
      final voice = _section(doc.values, 'voice');
      final stt = _section(doc.values, 'stt');
      final tts = _section(doc.values, 'tts');
      final sttOpts = _section(stt, 'options');
      final ttsOpts = _section(tts, 'options');
      if (!mounted) return;
      setState(() {
        _liveEnabled = voice['live_enabled'] == true;
        _sttBackend = stt['backend'] as String?;
        _ttsBackend = tts['backend'] as String?;
        _sttModel.text = sttOpts['model']?.toString() ?? '';
        _ttsVoice.text =
            ttsOpts['voice']?.toString() ?? ttsOpts['model']?.toString() ?? '';
        _maxSession.text = voice['live_max_session_secs']?.toString() ?? '';
        _maxUtterance.text =
            voice['live_max_utterance_secs']?.toString() ?? '';
        _silenceMs.text = voice['live_silence_timeout_ms']?.toString() ?? '';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  VoiceBackend? _lookup(List<VoiceBackend> list, String? id) {
    if (id == null) return null;
    for (final b in list) {
      if (b.id == id) return b;
    }
    return null;
  }

  Future<void> _save() async {
    final changes = <String, dynamic>{'voice.live_enabled': _liveEnabled};
    if (_sttBackend != null && _sttBackend!.isNotEmpty) {
      changes['stt.backend'] = _sttBackend!;
    }
    final sttModel = _sttModel.text.trim();
    if (sttModel.isNotEmpty) changes['stt.options.model'] = sttModel;
    if (_ttsBackend != null && _ttsBackend!.isNotEmpty) {
      changes['tts.backend'] = _ttsBackend!;
    }
    final ttsVoice = _ttsVoice.text.trim();
    if (ttsVoice.isNotEmpty) changes['tts.options.voice'] = ttsVoice;
    final session = int.tryParse(_maxSession.text.trim());
    if (session != null && session > 0) {
      changes['voice.live_max_session_secs'] = session;
    }
    final utterance = int.tryParse(_maxUtterance.text.trim());
    if (utterance != null && utterance > 0) {
      changes['voice.live_max_utterance_secs'] = utterance;
    }
    final silence = int.tryParse(_silenceMs.text.trim());
    if (silence != null && silence > 0) {
      changes['voice.live_silence_timeout_ms'] = silence;
    }
    setState(() => _saving = true);
    try {
      await widget.api.putConfig(changes);
      if (!mounted) return;
      toast(context, 'Voice settings saved.');
    } catch (e) {
      if (mounted) toastError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _backendDropdown({
    required String label,
    required List<VoiceBackend> backends,
    required String? value,
    required ValueChanged<String?> onChanged,
  }) {
    final items = backends
        .map((b) => DropdownMenuItem<String>(
              value: b.id,
              child: Text(
                b.recommended ? '${b.label} (recommended)' : b.label,
                style: PT.body.copyWith(fontSize: 14),
                overflow: TextOverflow.ellipsis,
              ),
            ))
        .toList();
    // Keep the current value selectable even if it isn't in the registry.
    if (value != null && !backends.any((b) => b.id == value)) {
      items.add(DropdownMenuItem<String>(
        value: value,
        child: Text(value, style: PT.body.copyWith(fontSize: 14)),
      ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: PT.meta),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: value,
          items: items,
          onChanged: onChanged,
          style: PT.body.copyWith(fontSize: 14),
          dropdownColor: P.surface,
          decoration: const InputDecoration(
            contentPadding:
                EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _keyHint(VoiceBackend? backend) {
    final keyEnv = backend?.keyEnv;
    if (backend == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        keyEnv == null
            ? 'No API key needed — runs locally or via your own command.'
            : 'API key: $keyEnv — set it under More → Keys.',
        style: PT.meta.copyWith(color: P.inkFaint),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded,
                color: P.inkSecondary, weight: 1.6),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: P.accent))
          : _error != null
              ? EmptyState(
                  icon: Icons.mic_off_outlined,
                  title: 'Couldn\'t load voice config',
                  body: _error!,
                  ctaLabel: 'Retry',
                  onCta: _load,
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  children: [
                    PCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text('Live voice mode',
                                        style: PT.sectionTitle),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Call-style voice sessions from the chat screen. Opt-in and off by default.',
                                      style: PT.meta,
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: _liveEnabled,
                                activeTrackColor: P.accent,
                                onChanged: (v) =>
                                    setState(() => _liveEnabled = v),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _numField(
                                    _maxSession, 'Max session (s)'),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _numField(
                                    _maxUtterance, 'Max utterance (s)'),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _numField(
                                    _silenceMs, 'Silence (ms)'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Blank keeps the server defaults (600s session, 30s utterance, 1200ms silence).',
                            style:
                                PT.meta.copyWith(color: P.inkFaint),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    PCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Speech to text',
                              style: PT.sectionTitle),
                          const SizedBox(height: 2),
                          Text(
                            'Transcribes voice notes and live utterances.',
                            style: PT.meta,
                          ),
                          const SizedBox(height: 12),
                          _backendDropdown(
                            label: 'Provider',
                            backends: _sttBackends,
                            value: _sttBackend,
                            onChanged: (v) =>
                                setState(() => _sttBackend = v),
                          ),
                          _keyHint(_lookup(_sttBackends, _sttBackend)),
                          const SizedBox(height: 12),
                          Text('Model', style: PT.meta),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _sttModel,
                            style: PT.body.copyWith(fontSize: 14),
                            decoration: const InputDecoration(
                              hintText: 'e.g. whisper-large-v3',
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    PCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Text to speech',
                              style: PT.sectionTitle),
                          const SizedBox(height: 2),
                          Text(
                            'Speaks agent replies in live voice mode.',
                            style: PT.meta,
                          ),
                          const SizedBox(height: 12),
                          _backendDropdown(
                            label: 'Provider',
                            backends: _ttsBackends,
                            value: _ttsBackend,
                            onChanged: (v) =>
                                setState(() => _ttsBackend = v),
                          ),
                          _keyHint(_lookup(_ttsBackends, _ttsBackend)),
                          const SizedBox(height: 12),
                          Text('Voice / model', style: PT.meta),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _ttsVoice,
                            style: PT.body.copyWith(fontSize: 14),
                            decoration: const InputDecoration(
                              hintText: 'e.g. af_sky or a model id',
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: GradientButton(
                        label: _saving ? 'Saving…' : 'Save voice settings',
                        onTap: _saving ? null : _save,
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _numField(TextEditingController ctrl, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: PT.meta),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          style: PT.body.copyWith(fontSize: 14),
          decoration: const InputDecoration(
            contentPadding:
                EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ],
    );
  }
}
