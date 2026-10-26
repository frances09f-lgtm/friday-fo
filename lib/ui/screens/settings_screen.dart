import '../stitch_style.dart';
import '../friday_motion.dart';
import 'package:flutter/services.dart';
import 'agent_mode_screen.dart';
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
  Map<String, dynamic>? _permissions;
  bool _localFallback = true;
  bool _speakReplies = true;
  LocalModelService get _local => context.read<LocalModelService>();
  String _modelStatus = '';
  @override
  void initState() {
    super.initState();
    _readPermissions();
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
  Future<void> _readPermissions() async {
    try {
      final state = await const MethodChannel('friday/device').invokeMapMethod<String, dynamic>('assistantState');
      if (mounted) setState(() => _permissions = state);
    } catch (_) {}
  }
  @override
  void dispose() {
    _gemini.dispose(); _groq.dispose(); _openRouter.dispose();
    _groqModel.dispose(); _openRouterModel.dispose(); _modelUrl.dispose();
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
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved')));
  }
  Future<void> _loadLocalModel() async {
    if (context.read<FridayAgent?>()?.running == true || _local.setupBusy) return;
    setState(() => _modelStatus = 'Downloading model...');
    final ok = await _local.installFromUrl(_modelUrl.text);
    setState(() {
      _modelStatus = ok ? 'Model installed on this phone.' : 'Download failed. Check the URL and connection.';
    });
  }
  Widget _tile({Widget? leading, required Widget title, Widget? subtitle, Widget? trailing, GestureTapCallback? onTap, EdgeInsetsGeometry? contentPadding}) =>
    MotionPress(enabled: onTap != null, child: ListTile(leading: leading, title: title,
      subtitle: subtitle, trailing: trailing, onTap: onTap, contentPadding: contentPadding));
  Widget _sectionLabel(String title) => Padding(padding: const EdgeInsets.only(left: 4, bottom: 10),
    child: Text(title, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600)));
  @override
  Widget build(BuildContext context) {
    final local = context.watch<LocalModelService>();
    final s = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('Settings', style: Stitch.title(25))),
      body: MotionList(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
        Text('Make Friday work for you.', style: TextStyle(color: s.onSurfaceVariant, fontSize: 15)),
        const SizedBox(height: 20),
        _sectionLabel('Get started'),
        MotionCard(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8), child: Column(children: [
          _tile(leading: Icon(Icons.assistant_outlined, color: s.primary), title: const Text('Assistant setup'),
            subtitle: const Text('Microphone, floating assistant & power button'), trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MotionRoute(builder: (_) => const AssistantSetupScreen())).then((_) => _readPermissions())),
          Divider(color: s.outlineVariant, indent: 56, height: 1),
          _tile(leading: Icon(Icons.contact_phone_outlined, color: s.primary), title: const Text('Contact nicknames & saved matches'),
            subtitle: const Text('Add, edit or forget call nicknames and remembered name matches'),
            onTap: () async {
              try { await const MethodChannel('friday/device').invokeMethod('manageSavedCallMatches'); }
              catch (_) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Open Friday on Android to manage saved matches.'))); }
            }),
          _tile(leading: Icon(Icons.devices_outlined, color: s.primary), title: const Text('Connected devices'),
            subtitle: const Text('Pair Friday on another device'), trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MotionRoute(builder: (_) => const DeviceLinkScreen()))),
        ])),
        const SizedBox(height: 20), _sectionLabel('Voice'),
        MotionCard(color: s.tertiaryContainer, padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: MotionSwitchTile(title: const Text('Speak replies out loud'), subtitle: const Text('Turn off for quiet replies'),
            value: _speakReplies, onChanged: (value) => setState(() => _speakReplies = value))),
        const SizedBox(height: 20), _sectionLabel('More settings'),
        MotionCard(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8), child:
          MotionExpansion(leading: const Icon(Icons.psychology_outlined), title: const Text('AI & models'),
            subtitle: Text(local.isReady ? 'On-device model loaded' : 'On-device model not loaded'),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 18), children: [
              _tile(contentPadding: EdgeInsets.zero, title: const Text('Qwen local model'),
                subtitle: const Text('Manage the existing .task model'), trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, MotionRoute(builder: (_) => const LocalModelSetupScreen()))),
              MotionSwitchTile(contentPadding: EdgeInsets.zero, title: const Text('On-device fallback'),
                subtitle: const Text('Used when cloud services are unavailable'), value: _localFallback,
                onChanged: (value) => setState(() => _localFallback = value)),
              MotionExpansion(tilePadding: EdgeInsets.zero, title: const Text('Cloud fallback keys'),
                subtitle: const Text('Gemini, Groq and OpenRouter'), children: [
                  const Text('Tried in order: Gemini, then Groq, then OpenRouter. Any one is enough.'),
                  const SizedBox(height: 12),
                  _KeyField(controller: _gemini, label: 'Gemini API key', hint: 'aistudio.google.com/apikey'),
                  _KeyField(controller: _groq, label: 'Groq API key', hint: 'console.groq.com/keys'),
                  _KeyField(controller: _openRouter, label: 'OpenRouter API key', hint: 'openrouter.ai/keys'),
                  TextField(controller: _groqModel, decoration: const InputDecoration(labelText: 'Groq model')),
                  const SizedBox(height: 12),
                  TextField(controller: _openRouterModel, decoration: const InputDecoration(labelText: 'OpenRouter model')),
                ]),
              if (!kIsWeb && (Platform.isAndroid || Platform.isIOS))
                MotionExpansion(tilePadding: EdgeInsets.zero, title: const Text('Advanced legacy .task installer'),
                  subtitle: const Text('Only runs when you choose Install'), children: [
                    TextField(controller: _modelUrl, decoration: const InputDecoration(labelText: 'Advanced legacy model URL (.task)')),
                    const SizedBox(height: 12),
                    MotionPress(child: OutlinedButton.icon(onPressed: _loadLocalModel, icon: const Icon(Icons.download), label: const Text('Install specified .task'))),
                    if (_modelStatus.isNotEmpty) Text(_modelStatus),
                  ]),
            ])),
        const SizedBox(height: 12),
        MotionCard(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8), child:
          MotionExpansion(leading: const Icon(Icons.shield_outlined), title: const Text('Permissions & phone controls'),
            subtitle: const Text('Review access and screen actions'), children: [
              _tile(title: const Text('Accessibility Service'), subtitle: const Text('Accessible screen text and checked actions'),
                trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.push(context, MotionRoute(builder: (_) => const AgentModeScreen()))),
              _tile(title: const Text('Microphone'), subtitle: Text(_permissions == null ? 'Permission not checked' : _permissions!['microphone'] == true ? 'Allowed by Android' : 'Permission needed'),
                onTap: () => Navigator.push(context, MotionRoute(builder: (_) => const AssistantSetupScreen())).then((_) => _readPermissions())),
              _tile(title: const Text('Floating assistant'), subtitle: Text(_permissions == null ? 'Permission not checked' : _permissions!['overlay'] == true ? 'Display over other apps allowed' : 'Display-over-apps permission needed'),
                onTap: () => Navigator.push(context, MotionRoute(builder: (_) => const AssistantSetupScreen())).then((_) => _readPermissions())),
              if (!kIsWeb && Platform.isAndroid)
                _tile(title: const Text('Spotify controls'), subtitle: const Text('Optional notification access'),
                  onTap: () => Navigator.push(context, MotionRoute(builder: (_) => const SpotifyControlsScreen()))),
            ])),
        const SizedBox(height: 12),
        MotionCard(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8), child:
          _tile(leading: const Icon(Icons.help_outline), title: const Text('Commands'), subtitle: const Text('What Friday can do'),
            trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.push(context, MotionRoute(builder: (_) => const CommandsScreen())))),
        const SizedBox(height: 24),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.lock_outline, size: 16, color: s.onSurfaceVariant), const SizedBox(width: 9),
          Expanded(child: Text('Provider keys stay in secure storage. Screen-action safety checks stay on.',
            style: TextStyle(color: s.onSurfaceVariant, fontSize: 12, height: 1.5)))
        ]),
        if (!kIsWeb && Platform.isWindows)
          Padding(padding: const EdgeInsets.only(top: 12), child: Text('Windows voice input uses your Groq key. Tap the microphone to start, then tap again to stop and send.', style: TextStyle(fontSize: 12, color: s.onSurfaceVariant))),
        const SizedBox(height: 24),
        MotionPress(child: FilledButton.icon(onPressed: _save, icon: const Icon(Icons.check_rounded), label: const Text('Save changes'),
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)))),
      ]));
  }
}
class _KeyField extends StatelessWidget {
  const _KeyField({required this.controller, required this.label, required this.hint});
  final TextEditingController controller;
  final String label;
  final String hint;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 12),
    child: TextField(controller: controller, obscureText: true,
      decoration: InputDecoration(labelText: label, helperText: hint,
        fillColor: Theme.of(context).colorScheme.surfaceContainerLowest,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none))));
}
