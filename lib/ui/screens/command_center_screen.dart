import 'agent_mode_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/friday_controller.dart';
import '../../services/speech/speech_service.dart';
import '../../services/agent/friday_agent.dart';
import '../stitch_style.dart';
import '../responsive_globe.dart';
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
    final c = context.read<FridayController>();
    if (c.busy || input.text.trim().isEmpty) return;
    final text = input.text;
    input.clear();
    c.send(text);
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
    if (text != null && text.trim().isNotEmpty && mounted) {
      context.read<FridayController>().send('$prefix ${text.trim()}');
    }
  }

  void moreActions() => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
          child: SingleChildScrollView(
              child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('What would you like to do?',
                            style: Stitch.title(23)),
                        const SizedBox(height: 8),
                        for (final action
                            in <(IconData, String, String, VoidCallback)>[
                          (
                            Icons.document_scanner_outlined,
                            'Read my screen',
                            'Read accessible text on this phone',
                            () => context
                                .read<FridayController>()
                                .send('read my screen')
                          ),
                          (
                            Icons.smart_display_outlined,
                            'Open YouTube',
                            'Launch the app',
                            () => context
                                .read<FridayController>()
                                .send('open YouTube')
                          ),
                          (
                            Icons.alarm_outlined,
                            'Set alarm',
                            'Choose a time',
                            () => command('Set alarm', 'set alarm for')
                          ),
                          (
                            Icons.call_outlined,
                            'Call someone',
                            'Choose a contact',
                            () => command('Call someone', 'call')
                          ),
                          (
                            Icons.graphic_eq,
                            'Voice session',
                            'Open the full-screen voice view',
                            () => open(const ImmersiveVoiceScreen())
                          ),
                          (
                            Icons.smart_toy_outlined,
                            'Agent Mode',
                            'Review screen-task details and controls',
                            () => open(const AgentModeScreen())
                          ),
                        ])
                          ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(action.$1, color: Stitch.cyan),
                              title: Text(action.$2),
                              subtitle: Text(action.$3),
                              trailing:
                                  const Icon(Icons.chevron_right, size: 20),
                              onTap: () {
                                Navigator.pop(sheet);
                                action.$4();
                              }),
                      ])))));

  Widget composer(FridayController c) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
      child: SafeArea(
          top: false,
          bottom: false,
          child: Container(
              decoration: BoxDecoration(
                  color: Stitch.low,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Stitch.high)),
              padding: const EdgeInsets.fromLTRB(18, 5, 6, 5),
              child: Row(children: [
                Expanded(
                    child: TextField(
                        controller: input,
                        textInputAction: TextInputAction.send,
                        minLines: 1,
                        maxLines: 4,
                        onSubmitted: (_) {
                          if (!c.busy) send();
                        },
                        decoration: const InputDecoration(
                            hintText: 'Type a message…',
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none))),
                IconButton.filled(
                    tooltip: 'Send',
                    onPressed: c.busy ? null : send,
                    icon: const Icon(Icons.arrow_upward, size: 22))
              ]))));

  @override
  Widget build(BuildContext context) {
    final c = context.watch<FridayController>();
    final speech = context.read<SpeechService>();
    final busy = c.busy || (context.watch<FridayAgent?>()?.running ?? false);
    return ListenableBuilder(
        listenable: speech.activity,
        builder: (context, _) {
          final listening = speech.isListening ||
              speech.activity.value == SpeechActivity.listening;
          final status = busy ? c.phase : 'Tap to talk, or type below';
          final speaking = speech.activity.value == SpeechActivity.speaking;
          final globeListening =
              speech.activity.value == SpeechActivity.listening;
          final globeMode = speaking
              ? GlobeMode.speaking
              : globeListening
                  ? GlobeMode.listening
                  : busy
                      ? GlobeMode.thinking
                      : GlobeMode.idle;
          return Scaffold(
              appBar: AppBar(
                  title: Text(
                      tab == 0
                          ? 'Friday'
                          : tab == 1
                              ? 'Tasks'
                              : 'Activity',
                      style: Stitch.title(23)),
                  titleSpacing: 22,
                  actions: [
                    if (tab == 0)
                      IconButton(
                          tooltip: 'Chat history',
                          icon: const Icon(Icons.chat_bubble_outline_rounded),
                          onPressed: () => open(const HomeScreen())),
                    IconButton(
                        tooltip: 'Settings',
                        icon: const Icon(Icons.tune_rounded),
                        onPressed: () =>
                            Navigator.pushNamed(context, '/settings')),
                    const SizedBox(width: 8)
                  ]),
              body: IndexedStack(index: tab, children: [
                Column(children: [
                  Expanded(
                      child: LayoutBuilder(
                          builder: (context, constraints) =>
                              SingleChildScrollView(
                                  child: ConstrainedBox(
                                      constraints: BoxConstraints(
                                          minHeight: constraints.maxHeight),
                                      child: Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                              24, 20, 24, 16),
                                          child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                ResponsiveGlobe(
                                                  mode: globeMode,
                                                  active: tab == 0 &&
                                                      (ModalRoute.of(context)
                                                              ?.isCurrent ??
                                                          true),
                                                  onTap: speaking
                                                      ? () {
                                                          speech.stopSpeaking();
                                                        }
                                                      : busy
                                                          ? null
                                                          : talk,
                                                ),
                                                const SizedBox(height: 28),
                                                Text('What can I help with?',
                                                    textAlign: TextAlign.center,
                                                    style: Stitch.title(29)),
                                                const SizedBox(height: 10),
                                                Text(
                                                    speaking
                                                        ? 'Speaking…'
                                                        : globeListening
                                                            ? 'Listening…'
                                                            : status,
                                                    textAlign: TextAlign.center,
                                                    style: const TextStyle(
                                                        color: Stitch.muted,
                                                        fontSize: 15,
                                                        height: 1.5)),
                                                const SizedBox(height: 26),
                                                FilledButton.icon(
                                                    style: FilledButton.styleFrom(
                                                        backgroundColor:
                                                            Stitch.cyan,
                                                        foregroundColor:
                                                            const Color(
                                                                0xFF08232A),
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                                horizontal: 28,
                                                                vertical: 17)),
                                                    onPressed:
                                                        busy ? null : talk,
                                                    icon: Icon(listening
                                                        ? Icons.stop_rounded
                                                        : Icons.mic_rounded),
                                                    label: Text(
                                                        listening
                                                            ? 'Stop listening'
                                                            : 'Talk to Friday',
                                                        style: const TextStyle(
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            fontSize: 16))),
                                                const SizedBox(height: 12),
                                                TextButton.icon(
                                                    onPressed: moreActions,
                                                    icon: const Icon(
                                                        Icons.grid_view_rounded,
                                                        size: 17),
                                                    label: const Text(
                                                        'More actions')),
                                                if (c.partialHeard.isNotEmpty)
                                                  Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                              top: 12),
                                                      child: Text(
                                                          c.partialHeard,
                                                          textAlign: TextAlign
                                                              .center)),
                                                if (micError != null)
                                                  Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                              top: 12),
                                                      child: Text(micError!,
                                                          textAlign:
                                                              TextAlign.center,
                                                          style: const TextStyle(
                                                              color: Color(
                                                                  0xFFFFB4AB)))),
                                              ])))))),
                  composer(c),
                ]),
                BackgroundTasksScreen(
                    embedded: true, onCreate: () => open(const HomeScreen())),
                _activity(c),
              ]),
              bottomNavigationBar: NavigationBar(
                  height: 72,
                  backgroundColor: Stitch.bg,
                  indicatorColor: Stitch.cyan.withValues(alpha: .12),
                  selectedIndex: tab,
                  onDestinationSelected: (value) => setState(() => tab = value),
                  destinations: const [
                    NavigationDestination(
                        icon: Icon(Icons.auto_awesome_outlined),
                        selectedIcon: Icon(Icons.auto_awesome),
                        label: 'Home'),
                    NavigationDestination(
                        icon: Icon(Icons.checklist_rounded), label: 'Tasks'),
                    NavigationDestination(
                        icon: Icon(Icons.history_rounded), label: 'Activity'),
                  ]));
        });
  }

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
