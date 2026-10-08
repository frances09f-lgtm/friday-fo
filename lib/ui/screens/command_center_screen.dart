import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/chat_message.dart';
import '../../state/friday_controller.dart';
import '../../services/speech/speech_service.dart';
import 'home_screen.dart';
import 'connected_apps_screen.dart';
import 'background_tasks_screen.dart';
import 'assistant_setup_screen.dart';
import 'device_link_screen.dart';
import 'notifications_screen.dart';

class CommandCenterScreen extends StatefulWidget {
  const CommandCenterScreen({super.key});
  @override
  State<CommandCenterScreen> createState() => _CommandCenterScreenState();
}

class _CommandCenterScreenState extends State<CommandCenterScreen> {
  int tab = 0;
  bool ready = false;
  String? micError;
  @override
  void initState() {
    super.initState();
    context.read<SpeechService>().initSpeech().then((v) {
      if (mounted) setState(() => ready = v);
    });
  }

  Future<void> talk() async {
    final s = context.read<SpeechService>();
    final c = context.read<FridayController>();
    if (c.busy) return;
    if (s.isListening) {
      await s.stopListening();
      if (mounted) setState(() {});
      return;
    }
    if (!ready) {
      setState(
        () => micError =
            'Microphone is not ready. Open Assistant setup to check permission.',
      );
      return;
    }
    c.setPartialHeard('');
    s.startListening(
      onResult: (t) {
        c.setPartialHeard(t);
        if (mounted) setState(() {});
      },
      onDone: () {
        if (mounted) {
          setState(() => micError = s.lastSttError);
          final text = c.partialHeard;
          if (text.trim().isNotEmpty) c.send(text);
        }
      },
    );
    setState(() => micError = null);
  }

  Future<void> command(String label, String prefix) async {
    final input = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(label),
        content: TextField(
          controller: input,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Enter the command details',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, input.text),
            child: const Text('Run'),
          ),
        ],
      ),
    );
    input.dispose();
    if (text != null && text.trim().isNotEmpty && mounted)
      context.read<FridayController>().send('$prefix ${text.trim()}');
  }

  void open(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  @override
  Widget build(BuildContext context) {
    final c = context.watch<FridayController>();
    final s = context.read<SpeechService>();
    final status = s.isListening ? 'Listening' : c.phase;
    final lastCommand =
        c.messages.where((m) => m.role == MessageRole.user).lastOrNull;
    final lastResult =
        c.messages.where((m) => m.role == MessageRole.friday).lastOrNull;
    return Scaffold(
      appBar: tab == 1
          ? null
          : AppBar(
              title: Text(tab == 0 ? 'Friday' : 'Activity'),
              actions: [
                IconButton(
                  tooltip: 'Notifications',
                  onPressed: () => open(const NotificationsScreen()),
                  icon: const Icon(Icons.notifications_outlined),
                ),
                IconButton(
                  tooltip: 'Pair devices',
                  onPressed: () => open(const DeviceLinkScreen()),
                  icon: const Icon(Icons.devices),
                ),
                IconButton(
                  tooltip: 'Assistant setup',
                  onPressed: () => open(const AssistantSetupScreen()),
                  icon: const Icon(Icons.assistant),
                ),
                IconButton(
                  tooltip: 'Settings',
                  onPressed: () => Navigator.pushNamed(context, '/settings'),
                  icon: const Icon(Icons.settings),
                ),
              ],
            ),
      body: IndexedStack(
        index: tab,
        children: [
          ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 24),
              const Center(
                child: Text(
                  'What do you want me to do?',
                  style: TextStyle(fontSize: 23, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 28),
              Center(
                child: GestureDetector(
                  onTap: talk,
                  onLongPress: talk,
                  child: Semantics(
                    button: true,
                    label: 'Talk to Friday',
                    child: Container(
                      width: 168,
                      height: 168,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const RadialGradient(
                          colors: [Color(0xFFBBA0FF), Color(0xFF6750A4)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color:
                                const Color(0xFF9B7AE0).withValues(alpha: .25),
                            blurRadius: 40,
                            spreadRadius: 8,
                          ),
                        ],
                      ),
                      child: Icon(
                        s.isListening ? Icons.mic : Icons.graphic_eq,
                        color: Colors.white,
                        size: 64,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Center(child: Text(status, style: const TextStyle(fontSize: 17))),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  s.isListening ? 'Tap to stop' : 'Tap or hold to talk',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ),
              if (c.partialHeard.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(c.partialHeard, textAlign: TextAlign.center),
                ),
              if (micError != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(micError!),
                ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  ActionChip(
                    label: const Text('Call'),
                    avatar: const Icon(Icons.call, size: 18),
                    onPressed: () => command('Who should Friday call?', 'call'),
                  ),
                  ActionChip(
                    label: const Text('Reminder'),
                    avatar: const Icon(Icons.alarm, size: 18),
                    onPressed: () =>
                        command('Reminder, including the time', 'remind me to'),
                  ),
                  ActionChip(
                    label: const Text('YouTube'),
                    avatar: const Icon(Icons.play_circle_outline, size: 18),
                    onPressed: () => c.send('open youtube'),
                  ),
                  ActionChip(
                    label: const Text('Screen'),
                    avatar: const Icon(Icons.visibility_outlined, size: 18),
                    onPressed: () => showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Screen tools'),
                        content: const Text(
                          'Screen reading and tapping are not available in this version. Friday will not pretend to inspect another app.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  ActionChip(
                    label: const Text('Connected apps'),
                    avatar: const Icon(Icons.hub_outlined, size: 18),
                    onPressed: () => open(const ConnectedAppsScreen()),
                  ),
                  ActionChip(
                    label: const Text('Tasks'),
                    avatar: const Icon(Icons.task_alt, size: 18),
                    onPressed: () => open(const BackgroundTasksScreen()),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (lastCommand != null || lastResult != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Last command',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        if (lastCommand != null) Text(lastCommand.text),
                        if (lastResult != null) ...[
                          const SizedBox(height: 12),
                          Text(lastResult.text),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const HomeScreen(),
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Command history and actual results. No simulated screen-reading or tapping steps.',
              ),
              const SizedBox(height: 12),
              if (c.busy)
                Card(
                  child: ListTile(
                    leading: const CircularProgressIndicator(),
                    title: Text('Friday is ${c.phase.toLowerCase()}'),
                    subtitle: const Text(
                      'Waiting for the current command result',
                    ),
                  ),
                ),
              if (c.messages.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No activity yet. Give Friday a command.'),
                ),
              for (final m in c.messages.reversed.take(40))
                Card(
                  child: ListTile(
                    leading: Icon(
                      m.role == MessageRole.user
                          ? Icons.arrow_forward
                          : Icons.receipt_long,
                    ),
                    title: Text(
                      m.role == MessageRole.user ? 'Command' : 'Result',
                    ),
                    subtitle: Text(m.text),
                  ),
                ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (v) => setState(() => tab = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.blur_circular), label: 'Home'),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            label: 'Chat',
          ),
          NavigationDestination(icon: Icon(Icons.history), label: 'Activity'),
        ],
      ),
    );
  }
}
