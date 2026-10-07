import 'package:flutter/material.dart';
import '../../services/tasks/task_service.dart';

class BackgroundTasksScreen extends StatefulWidget {
  const BackgroundTasksScreen({super.key, this.service});
  final TaskService? service;
  @override
  State<BackgroundTasksScreen> createState() => _BackgroundTasksScreenState();
}

class _BackgroundTasksScreenState extends State<BackgroundTasksScreen> {
  late final TaskService service = widget.service ?? TaskService();
  Map<String, dynamic>? data;
  String? error;
  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    try {
      final value = await service.state();
      if (mounted)
        setState(() {
          data = value;
          error = null;
        });
    } catch (_) {
      if (mounted)
        setState(() => error = 'Could not read saved background tasks.');
    }
  }

  Future<void> change(Future<String> operation) async {
    try {
      final result = await operation;
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(result)));
    } catch (_) {
      if (mounted) setState(() => error = 'Could not change background tasks.');
    }
    await refresh();
  }

  @override
  Widget build(BuildContext context) {
    final tasks = (data?['tasks'] as List? ?? []).whereType<Map>().toList();
    return Scaffold(
        appBar: AppBar(title: const Text('Background tasks'), actions: [
          IconButton(onPressed: refresh, icon: const Icon(Icons.refresh))
        ]),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          const Text(
              'Gold alerts read Oro\'s saved quotes on this phone. They do not fetch live prices or place trades. Quotes more than 5 minutes old cannot trigger an alert.'),
          const SizedBox(height: 12),
          if (data?['runtime'] != null)
            Text('Last recorded execution: ${data!['runtime']}'),
          if (data?['mode'] == 'unsupported')
            const Text(
                'These checks run on the Android phone, where Oro is installed.')
          else if (data != null)
            SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Battery saver'),
                subtitle: const Text(
                    'Off: quiet ongoing notification, checks about every requested interval. On: checks at least 15 minutes apart, possibly later.'),
                value: data?['mode'] == 'battery_saver',
                onChanged: (v) => change(service.setMode(v))),
          const Text(
              'Tasks survive closing Friday. Force-stopping the app stops checks until you reopen it. After a reboot, checks use the slower worker until you reopen Friday.'),
          const SizedBox(height: 12),
          const Text(
              'Try: "check gold every 5 minutes and tell me if it goes below 4150". Alerts are one-shot.'),
          if (error != null)
            Text(error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (tasks.isEmpty && data != null)
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('No saved gold tasks.')),
          for (final t in tasks)
            Card(
                child: ListTile(
                    title: Text('Gold ${t['direction']} ${t['threshold']}'),
                    subtitle: Text(
                        '${t['status']} | every ${t['intervalMinutes']} min\n${t['lastOutcome']}'))),
          if (tasks.isNotEmpty)
            TextButton(
                onPressed: () => change(service.cancelAll()),
                child: const Text('Cancel all gold tasks')),
        ]));
  }
}
