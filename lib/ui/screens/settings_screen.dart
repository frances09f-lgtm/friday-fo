import '../stitch_style.dart';
import 'local_model_setup_screen.dart';
import '../../services/agent/friday_agent.dart';
import 'commands_screen.dart';
import 'spotify_controls_screen.dart';
import 'package:flutter/material.dart';
import 'assistant_setup_screen.dart';
import 'device_link_screen.dart';
import 'package:provider/provider.dart';

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

import '../../services/ai/local_model_service.dart';
import '../../services/storage/settings_store.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _gemini = TextEditingController();
  final _groq = TextEditingController();
  final _openRouter = TextEditingController();
  final _groqModel = TextEditingController();
  final _openRouterModel = TextEditingController();
  final _modelUrl = TextEditingController();
  bool _localFallback = true;
  bool _speakReplies = true;

  LocalModelService get _local => context.read<LocalModelService>();
  String _modelStatus = '';

  @override
  void initState() {
    super.initState();
    final s = context.read<SettingsStore>();
    _gemini.text = s.geminiKey;
    _groq.text = s.groqKey;
    _openRouter.text = s.openRouterKey;
    _groqModel.text = s.groqModel;
    _openRouterModel.text = s.openRouterModel;
    _modelUrl.text = s.localModelUrl;
    _localFallback = s.localFallbackEnabled;
    _speakReplies = s.speakReplies;
  }

  @override
  void dispose() {
    _gemini.dispose();
    _groq.dispose();
    _openRouter.dispose();
    _groqModel.dispose();
    _openRouterModel.dispose();
    _modelUrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = context.read<SettingsStore>();
    await s.setApiKey('gemini', _gemini.text);
    await s.setApiKey('groq', _groq.text);
    await s.setApiKey('openrouter', _openRouter.text);
    await s.setGroqModel(_groqModel.text);
    await s.setOpenRouterModel(_openRouterModel.text);
    await s.setLocalModelUrl(_modelUrl.text);
    await s.setLocalFallback(_localFallback);
    await s.setSpeakReplies(_speakReplies);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings saved')),
    );
  }

  Future<void> _loadLocalModel() async {
    if (context.read<FridayAgent?>()?.running == true || _local.setupBusy)
      return;
    setState(() => _modelStatus = 'Downloading model...');
    final ok = await _local.installFromUrl(_modelUrl.text);
    setState(() {
      _modelStatus = ok
          ? 'Model installed on this phone.'
          : 'Download failed. Check the URL and connection.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const StitchHeader(title: 'Overview', back: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(children: [
            const Icon(Icons.memory, color: Stitch.cyan, size: 18),
            const SizedBox(width: 8),
            Expanded(
                child: Text('AI ENGINE & ON-DEVICE INFERENCE',
                    style: Stitch.mono(11))),
            const StitchBadge('CPU')
          ]),
          const SizedBox(height: 14),
          StitchCard(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('Qwen 2.5 · 0.5B', style: Stitch.title(23)),
                const SizedBox(height: 8),
                const Text('Existing .task model · MediaPipe CPU inference',
                    style: TextStyle(color: Stitch.muted)),
                const SizedBox(height: 16),
                ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.radio_button_checked,
                        color: Stitch.cyan),
                    title: const Text('Qwen local model'),
                    subtitle: Text(context.watch<LocalModelService>().isReady
                        ? 'Loaded on this device'
                        : 'Load and test to check readiness'),
                    trailing:
                        const Icon(Icons.verified_outlined, color: Stitch.cyan),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const LocalModelSetupScreen()))),
                SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('On-device fallback'),
                    subtitle: const Text(
                        'Used when cloud keys fail or are unavailable'),
                    value: _localFallback,
                    onChanged: (v) => setState(() => _localFallback = v)),
                const SizedBox(height: 8),
                StitchCard(
                    color: Color(0xFF0B0E15),
                    padding: EdgeInsets.all(12),
                    child: Text('Saved Qwen file retained · No GGUF conversion',
                        style: Stitch.mono(10, Stitch.green))),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const LocalModelSetupScreen())),
                    icon: const Icon(Icons.memory),
                    label: const Text('Manage existing .task model'))
              ])),
          const SizedBox(height: 22),
          Row(children: [
            const Icon(Icons.shield_outlined, color: Stitch.cyan, size: 18),
            const SizedBox(width: 8),
            Text('SYSTEM PRIVILEGES & SETUP', style: Stitch.mono(11))
          ]),
          const SizedBox(height: 12),
          if (!kIsWeb && Platform.isAndroid)
            ListTile(
                title: const Text('Spotify controls'),
                subtitle: const Text('Review optional notification access'),
                leading: const Icon(Icons.music_note),
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const SpotifyControlsScreen()))),
          StitchCard(
              child: Column(children: [
            ListTile(
                title: const Text('Assistant setup'),
                subtitle:
                    const Text('Floating bar, microphone and power button'),
                leading: const Icon(Icons.assistant),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const AssistantSetupScreen()))),
            ListTile(
              leading: const Icon(Icons.devices),
              title: const Text('Connected devices'),
              subtitle:
                  const Text('Pair this phone with Friday on another device'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const DeviceLinkScreen())),
            ),
            Card(
                child: ListTile(
                    leading: const Icon(Icons.terminal),
                    title: const Text('Commands'),
                    subtitle:
                        const Text('All supported patterns and what they do'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const CommandsScreen())))),
          ])),
          const SizedBox(height: 24),
          StitchCard(
              child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Cloud fallback keys'),
                  subtitle: const Text('Gemini, Groq and OpenRouter'),
                  children: [
                Text('Cloud fallback keys',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                const Text(
                    'Tried in order: Gemini, then Groq, then OpenRouter. Any one is enough.'),
                const SizedBox(height: 12),
                _KeyField(
                    controller: _gemini,
                    label: 'Gemini API key',
                    hint: 'aistudio.google.com/apikey'),
                _KeyField(
                    controller: _groq,
                    label: 'Groq API key',
                    hint: 'console.groq.com/keys'),
                _KeyField(
                    controller: _openRouter,
                    label: 'OpenRouter API key',
                    hint: 'openrouter.ai/keys'),
                TextField(
                  controller: _groqModel,
                  decoration: const InputDecoration(
                    labelText: 'Groq model',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _openRouterModel,
                  decoration: const InputDecoration(
                    labelText: 'OpenRouter model',
                    border: OutlineInputBorder(),
                  ),
                ),
              ])),
          const SizedBox(height: 24),
          Row(children: [
            const Icon(Icons.record_voice_over_outlined,
                color: Stitch.blue, size: 18),
            const SizedBox(width: 8),
            Text('VOICE & AUDIO', style: Stitch.mono(11))
          ]),
          const SizedBox(height: 12),
          StitchCard(
              child: Column(children: [
            Text('Voice', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Speak replies out loud'),
              subtitle: const Text('Turn off to mute Friday'),
              value: _speakReplies,
              onChanged: (v) => setState(() => _speakReplies = v),
            ),
          ])),
          if (!kIsWeb && Platform.isWindows) ...[
            const Text(
              'Voice input: tap the mic to start talking, tap again to stop '
              'and send. Speech is transcribed with your Groq key; replies '
              'speak through Windows voices. If the mic stays silent, check '
              'Windows Settings > Privacy > Microphone.',
              style: TextStyle(fontSize: 12),
            ),
          ],
          const SizedBox(height: 16),
          if (!kIsWeb && (Platform.isAndroid || Platform.isIOS))
            ExpansionTile(
                title: const Text('Advanced legacy .task installer'),
                subtitle: const Text(
                    'Does not run unless you explicitly choose Install'),
                children: [
                  Text('On-device backup',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Use on-device model when keys fail'),
                    value: _localFallback,
                    onChanged: (v) => setState(() => _localFallback = v),
                  ),
                  TextField(
                    controller: _modelUrl,
                    decoration: const InputDecoration(
                      labelText: 'Advanced legacy model URL (.task)',
                      hintText: 'Optional existing .task source',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.download),
                        label: const Text('Install specified .task'),
                        onPressed: _loadLocalModel,
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(_modelStatus)),
                    ],
                  ),
                ]),
          const SizedBox(height: 24),
          StitchCard(
              color: Color(0xFF0B0E15),
              child: Row(children: [
                const Icon(Icons.fingerprint, color: Stitch.cyan),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(
                        'Provider keys stay in secure storage. Screen actions keep their existing safety checks.',
                        style: Stitch.mono(10)))
              ])),
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: const Icon(Icons.save),
            label: const Text('Save'),
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}

class _KeyField extends StatelessWidget {
  const _KeyField(
      {required this.controller, required this.label, required this.hint});

  final TextEditingController controller;
  final String label;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: controller,
        obscureText: true,
        decoration: InputDecoration(
          labelText: label,
          helperText: hint,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
