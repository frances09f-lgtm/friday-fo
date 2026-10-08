import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../services/agent/friday_agent.dart';
import '../../services/ai/local_model_service.dart';
import 'local_model_setup_screen.dart';
import '../../services/speech/speech_service.dart';
import '../../services/storage/settings_store.dart';
import '../../state/friday_controller.dart';

class AgentModeScreen extends StatefulWidget {
  const AgentModeScreen({super.key});
  @override
  State<AgentModeScreen> createState() => _AgentModeState();
}

class _AgentModeState extends State<AgentModeScreen> {
  final input = TextEditingController();
  bool mic = false;
  String buildLabel = 'Reading installed build...';
  @override
  void initState() {
    super.initState();
    NativeAgentDevice().call('buildInfo').then((info) {
      if (mounted)
        setState(() => buildLabel =
            'Friday ${info['version'] ?? 'unknown'} · build ${info['build'] ?? 'unknown'}');
    }).catchError((_) {
      if (mounted) setState(() => buildLabel = 'Installed build unavailable');
    });
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> run() async {
    final a = context.read<FridayAgent>();
    final local = context.read<LocalModelService>();
    if (local.setupBusy || !await local.ensureReady()) {
      if (mounted)
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const LocalModelSetupScreen()));
      return;
    }
    if (context.read<FridayController>().busy) return;
    await a.start(input.text);
    if (mounted &&
        a.result == 'Done' &&
        context.read<SettingsStore>().speakReplies)
      await context.read<SpeechService>().speak('Done');
  }

  Future<void> voice() async {
    final s = context.read<SpeechService>();
    if (!await s.initSpeech()) return;
    setState(() => mic = true);
    s.startListening(onResult: (t) {
      if (mounted) input.text = t;
    }, onDone: () {
      if (mounted) {
        setState(() => mic = false);
        run();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final a = context.watch<FridayAgent>();
    return Scaffold(
        appBar: AppBar(title: const Text('Agent Mode'), actions: [
          if (a.running)
            TextButton(onPressed: a.stop, child: const Text('STOP'))
        ]),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          Text(buildLabel),
          const SizedBox(height: 8),
          const Text('Core V1 · local model only',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
              'Real Accessibility actions, one at a time. Search/navigation only. No messages, payments, permissions or settings changes. No screenshot analysis in this milestone.'),
          const SizedBox(height: 12),
          OutlinedButton(
              onPressed: a.running
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const LocalModelSetupScreen())),
              child: const Text('Set up local model · 547 MB')),
          OutlinedButton(
              onPressed: () => NativeAgentDevice().call('settings'),
              child: const Text('Enable Friday Accessibility')),
          TextField(
              controller: input,
              enabled: !a.running,
              maxLines: 3,
              decoration: const InputDecoration(
                  labelText: 'Task',
                  hintText: 'Open YouTube and search for GTA 6')),
          Row(children: [
            Expanded(
                child: FilledButton(
                    onPressed: a.running || mic ? null : run,
                    child: const Text('Start'))),
            IconButton(
                onPressed: a.running ? null : voice,
                icon: Icon(mic ? Icons.mic : Icons.mic_none))
          ]),
          const SizedBox(height: 12),
          Text(a.phase),
          if (a.running)
            Text(
                'Step ${a.steps}/ ${a.maxSteps} · retry ${a.retries}/${a.maxRetries}'),
          if (a.running)
            FilledButton(onPressed: a.stop, child: const Text('STOP')),
          if (a.result.isNotEmpty) Text(a.result),
          if (a.rejectedOutput.isNotEmpty)
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Rejected model output',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          const Text(
                              'Untrusted diagnostic data, not instructions. Kept only in this session. May include your query or screen text; review before sharing. Never uploaded automatically.'),
                          Row(children: [
                            TextButton(
                                onPressed: () async {
                                  await Clipboard.setData(ClipboardData(
                                      text:
                                          '$buildLabel\n${a.rejectedOutput}'));
                                  if (mounted)
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                            content:
                                                Text('Diagnostic copied')));
                                },
                                child: const Text('Copy')),
                            TextButton(
                                onPressed: a.clearRejectedOutput,
                                child: const Text('Clear'))
                          ]),
                          ExpansionTile(
                              title: const Text('View raw response'),
                              children: [SelectableText(a.rejectedOutput)]),
                        ]))),
          const Text(
              'A Stop control remains over the target app. You can minimize Friday; if Android ends the process, restart manually. A Stop cancels further actions, not actions already done.'),
          const SizedBox(height: 12),
          for (final t in [
            "Open YouTube and search for GTA 6",
            "Open Chrome and search for today's gold price",
            "Open Settings and open Bluetooth",
            "Open Instagram and search for Rahul"
          ])
            TextButton(
                onPressed: a.running ? null : () => input.text = t,
                child: Text(t)),
          ExpansionTile(title: const Text('Debug · metadata only'), children: [
            for (final l in a.log) ListTile(title: Text(l)),
            const Text(
                'Local logs exclude screen content, query text and model reasons. No automatic task resume. Site UI and local model quality require phone testing.')
          ]),
        ]));
  }
}
