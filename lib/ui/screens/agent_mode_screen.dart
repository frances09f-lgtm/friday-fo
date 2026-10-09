import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:typed_data';
import '../../services/agent/agent_contract.dart';
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
  Uint8List? capture;
  String captureStatus = "";
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
    final goal = AgentGoal.parse(input.text);
    if (goal != null &&
        !goal.noPlanner &&
        (local.setupBusy || !await local.ensureReady())) {
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
          const Text('Screen control · local planner',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
              'Observe, plan, act and verify one step at a time. YouTube playback, WhatsApp chat navigation, ChatGPT questions and Instagram search. No WhatsApp sends, payments, permission approvals or login bypass. Uses the existing local .task model, not GGUF. Screen reading uses accessible text; image-only content may be unreadable.'),
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
          if (a.goal != null) Text('Task: ${a.goal!.task}'),
          if (a.currentApp.isNotEmpty) Text('App: ${a.currentApp}'),
          if (a.lastAction != null) Text('Action: ${a.lastAction!.action}'),
          if (a.running)
            Text(
                'Step ${a.steps}/ ${a.maxSteps} · retry ${a.retries}/${a.maxRetries}'),
          if (a.running)
            OutlinedButton(
                onPressed: () async {
                  final r = await NativeAgentDevice()
                      .call('screenshot')
                      .timeout(const Duration(seconds: 5));
                  if (mounted)
                    setState(() {
                      capture = r['bytes'] as Uint8List?;
                      captureStatus = r['success'] == true
                          ? 'Transient screenshot. Not stored or sent to a model.'
                          : r['error']?.toString() ?? 'Screenshot unavailable';
                    });
                },
                child: const Text('Preview screenshot · Android 11+')),
          if (captureStatus.isNotEmpty) Text(captureStatus),
          if (capture != null) ...[
            Image.memory(capture!),
            TextButton(
                onPressed: () => setState(() => capture = null),
                child: const Text('Clear screenshot'))
          ],
          if (a.running)
            FilledButton(onPressed: a.stop, child: const Text('STOP')),
          if (a.result.isNotEmpty) Text(a.result),
          if (!a.running && a.lastAction != null)
            ExpansionTile(
                title: const Text('Last decision · local diagnostic'),
                children: [
                  const Text(
                      'Untrusted model data or a task-derived opening step, not approval instructions. May contain query or screen text. Review before sharing.'),
                  SelectableText(const JsonEncoder.withIndent('  ')
                      .convert(a.lastAction!.json())),
                  TextButton(
                      onPressed: () => Clipboard.setData(ClipboardData(
                          text:
                              '$buildLabel\n${a.result}\n${const JsonEncoder.withIndent('  ').convert(a.lastAction!.json())}')),
                      child: const Text('Copy last decision')),
                ]),
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
            "Open YouTube and play GTA 6",
            "Open WhatsApp and open my chat with Rahul",
            "Open ChatGPT and search for explain gravity",
            "Tell me what is currently displayed on my screen",
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
