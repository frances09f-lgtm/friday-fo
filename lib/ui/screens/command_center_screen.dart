import 'agent_mode_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/friday_controller.dart';
import '../../services/speech/speech_service.dart';
import '../../services/ai/local_model_service.dart';
import '../../services/agent/friday_agent.dart';
import '../stitch_style.dart';
import 'home_screen.dart';
import 'background_tasks_screen.dart';
import 'immersive_voice_screen.dart';

class CommandCenterScreen extends StatefulWidget {
  const CommandCenterScreen({super.key});
  @override
  State<CommandCenterScreen> createState() => _CommandCenterScreenState();
}

class _CommandCenterScreenState extends State<CommandCenterScreen> {
  int tab = 0;
  bool ready = false;
  String? micError;
  final input = TextEditingController();
  @override
  void initState() {
    super.initState();
    context.read<SpeechService>().initSpeech().then((ok) {
      if (mounted) setState(() => ready = ok);
    });
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> talk() async {
    final s = context.read<SpeechService>(),
        c = context.read<FridayController>();
    if (c.busy || (context.read<FridayAgent?>()?.running ?? false)) return;
    if (s.isListening) {
      await s.stopListening();
      if (mounted) setState(() {});
      return;
    }
    if (!ready) {
      setState(() => micError =
          'Microphone is not ready. Open Assistant setup to check permission.');
      return;
    }
    c.setPartialHeard('');
    s.startListening(onResult: (t) {
      c.setPartialHeard(t);
      if (mounted) setState(() {});
    }, onDone: () {
      if (mounted) {
        setState(() => micError = s.lastSttError);
        final text = c.partialHeard;
        if (text.trim().isNotEmpty) c.send(text);
      }
    });
    setState(() => micError = null);
  }

  void open(Widget w) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => w));
  void send() {
    final text = input.text;
    input.clear();
    context.read<FridayController>().send(text);
  }

  Future<void> command(String title, String prefix) async {
    final field = TextEditingController();
    final text = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: Text(title),
                content: TextField(
                    controller: field,
                    autofocus: true,
                    decoration: const InputDecoration(
                        hintText: 'Enter command details')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, field.text),
                      child: const Text('Run'))
                ]));
    field.dispose();
    if (text != null && text.trim().isNotEmpty && mounted)
      context.read<FridayController>().send('$prefix ${text.trim()}');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<FridayController>(),
        local = context.watch<LocalModelService>();
    final s = context.read<SpeechService>();
    final status = s.isListening
        ? 'Listening closely...'
        : c.busy
            ? '${c.phase}...'
            : 'Ready when you are.';
    return Scaffold(
        appBar: tab == 1
            ? null
            : StitchHeader(
                title: tab == 0
                    ? 'Overview'
                    : tab == 2
                        ? 'Activity'
                        : 'Task Matrix',
                onVoice: () => open(const ImmersiveVoiceScreen()),
                onSettings: () => Navigator.pushNamed(context, '/settings')),
        body: IndexedStack(index: tab, children: [
          ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_greeting(), style: Stitch.mono(11)),
                      StitchBadge(local.isReady ? 'LOCAL READY' : 'LOCAL SETUP',
                          color: local.isReady ? Stitch.green : Stitch.muted)
                    ]),
                const SizedBox(height: 8),
                Text("I'm Friday.", style: Stitch.title(32)),
                const SizedBox(height: 4),
                const Text('Your personal ambient intelligence.',
                    style: TextStyle(color: Stitch.muted, fontSize: 15)),
                const SizedBox(height: 12),
                StitchCard(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(children: [
                      const Icon(Icons.memory, size: 16, color: Stitch.cyan),
                      const SizedBox(width: 8),
                      Text('Qwen 2.5 · 0.5B', style: Stitch.mono()),
                      const Spacer(),
                      const StitchBadge('ON-DEVICE')
                    ])),
                const SizedBox(height: 28),
                Center(
                    child: GestureDetector(
                        onTap: talk,
                        child: Semantics(
                            button: true,
                            label: 'Talk to Friday',
                            child: FridayOrb()))),
                const SizedBox(height: 12),
                Center(child: Text(status, style: Stitch.title(20))),
                const SizedBox(height: 6),
                Center(
                    child: Text(
                        s.isListening
                            ? 'MICROPHONE LISTENING'
                            : 'TAP THE CORE TO TALK',
                        style: Stitch.mono(10, Stitch.cyan))),
                const SizedBox(height: 16),
                Row(children: [
                  for (final name in [
                    'Idle',
                    'Listening',
                    'Thinking',
                    'Speaking'
                  ])
                    Expanded(
                        child: Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: StitchBadge(name,
                                color: (s.isListening && name == 'Listening') ||
                                        (!s.isListening &&
                                            !c.busy &&
                                            name == 'Idle') ||
                                        (c.busy && name == 'Thinking')
                                    ? Stitch.cyan
                                    : Stitch.muted)))
                ]),
                const SizedBox(height: 28),
                StitchCard(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    child: Row(children: [
                      const Icon(Icons.auto_fix_high,
                          size: 20, color: Stitch.muted),
                      const SizedBox(width: 8),
                      Expanded(
                          child: TextField(
                              controller: input,
                              onSubmitted: (_) => send(),
                              decoration: const InputDecoration(
                                  hintText: 'Ask Friday anything...',
                                  filled: false,
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none))),
                      IconButton(
                          tooltip: 'Send',
                          onPressed: c.busy ? null : send,
                          icon: const Icon(Icons.arrow_upward))
                    ])),
                const SizedBox(height: 18),
                Center(
                    child: FilledButton(
                        style: FilledButton.styleFrom(
                            backgroundColor: Stitch.cyan,
                            foregroundColor: const Color(0xFF002C72),
                            shape: const CircleBorder(),
                            padding: const EdgeInsets.all(20)),
                        onPressed: talk,
                        child: Icon(s.isListening ? Icons.stop : Icons.mic,
                            size: 30))),
                const SizedBox(height: 8),
                Center(
                    child: Text('Push to talk · microphone permission required',
                        style: Stitch.mono(9))),
                if (c.partialHeard.isNotEmpty)
                  Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(c.partialHeard, textAlign: TextAlign.center)),
                if (micError != null)
                  Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(micError!)),
                const SizedBox(height: 26),
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('QUICK COMMANDS', style: Stitch.mono(11)),
                      Text('Phone controls',
                          style: Stitch.mono(10, Stitch.cyan))
                    ]),
                const SizedBox(height: 8),
                _quick(
                    'Read my screen',
                    'Accessible text on this phone',
                    Icons.document_scanner,
                    Stitch.blue,
                    () => c.send('read my screen')),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                      child: _quick(
                          'Open YouTube',
                          'App launch',
                          Icons.smart_display,
                          const Color(0xFFFFB4AB),
                          () => c.send('open YouTube'))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _quick(
                          'Set alarm',
                          'Choose a time',
                          Icons.alarm,
                          Stitch.cyan,
                          () => command('Set alarm', 'set alarm for')))
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                      child: _quick(
                          'Call someone',
                          'Choose a contact',
                          Icons.call,
                          Stitch.green,
                          () => command('Call someone', 'call'))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _quick(
                          'Ask AI Core',
                          'Chat with Friday',
                          Icons.psychology_alt,
                          Stitch.blue,
                          () => setState(() => tab = 1)))
                ]),
                const SizedBox(height: 24),
                StitchCard(
                    color: const Color(0xFF0B0E15),
                    padding: const EdgeInsets.all(10),
                    child: Row(children: [
                      const Icon(Icons.memory, color: Stitch.cyan, size: 14),
                      const SizedBox(width: 6),
                      Expanded(
                          child: Text(
                              local.isReady ? 'Qwen loaded' : 'Qwen not loaded',
                              style: Stitch.mono(10))),
                      Text('CPU · .task', style: Stitch.mono(10, Stitch.green))
                    ])),
                TextButton.icon(
                    onPressed: () => open(const AgentModeScreen()),
                    icon: const Icon(Icons.smart_toy_outlined),
                    label: const Text('Agent Mode · screen task details')),
                if (c.messages.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('LATEST RESULT', style: Stitch.mono(10)),
                  const SizedBox(height: 8),
                  StitchCard(child: Text(c.messages.last.text)),
                  TextButton(
                      onPressed: () => setState(() => tab = 1),
                      child: const Text('Open conversation'))
                ]
              ]),
          const HomeScreen(),
          _activity(c),
          BackgroundTasksScreen(
              embedded: true, onCreate: () => setState(() => tab = 1))
        ]),
        bottomNavigationBar: NavigationBar(
            backgroundColor: const Color(0xFF0B0E15),
            indicatorColor: Stitch.low,
            selectedIndex: tab,
            onDestinationSelected: (v) {
              if (v == 4) {
                Navigator.pushNamed(context, '/settings');
              } else {
                setState(() => tab = v);
              }
            },
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.auto_awesome), label: 'Home'),
              NavigationDestination(
                  icon: Icon(Icons.chat_bubble_outline), label: 'Chat'),
              NavigationDestination(
                  icon: Icon(Icons.stacked_line_chart), label: 'Activity'),
              NavigationDestination(
                  icon: Icon(Icons.checklist), label: 'Tasks'),
              NavigationDestination(icon: Icon(Icons.tune), label: 'Settings')
            ]));
  }

  String _greeting() {
    final h = DateTime.now().hour;
    return h < 12
        ? 'GOOD MORNING'
        : h < 17
            ? 'GOOD AFTERNOON'
            : 'GOOD EVENING';
  }

  Widget _quick(String title, String subtitle, IconData icon, Color color,
          VoidCallback action) =>
      Material(
          color: Stitch.low,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: action,
              child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                            color: color.withValues(alpha: .12),
                            borderRadius: BorderRadius.circular(12)),
                        child: Icon(icon, color: color, size: 22)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600)),
                          Text(subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Stitch.mono(9))
                        ]))
                  ]))));
  Widget _activity(FridayController c) =>
      ListView(padding: const EdgeInsets.all(20), children: [
        Text('Activity', style: Stitch.title(30)),
        const SizedBox(height: 6),
        const Text(
            'Command history and actual results. No simulated execution steps.',
            style: TextStyle(color: Stitch.muted)),
        const SizedBox(height: 20),
        if (c.busy)
          StitchCard(child: Text('Friday is ${c.phase.toLowerCase()}')),
        if (c.messages.isEmpty)
          const StitchCard(
              child: Text('No activity yet. Give Friday a command.')),
        for (final m in c.messages.reversed.take(40))
          Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: StitchCard(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(
                        '${m.role.name.toUpperCase()} · ${m.at.hour.toString().padLeft(2, '0')}:${m.at.minute.toString().padLeft(2, '0')}',
                        style: Stitch.mono(10, Stitch.cyan)),
                    const SizedBox(height: 8),
                    SelectableText(m.text)
                  ])))
      ]);
}
