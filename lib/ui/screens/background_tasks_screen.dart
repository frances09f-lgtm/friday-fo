import 'package:flutter/material.dart';
import '../../services/tasks/task_service.dart';
import '../stitch_style.dart';

class BackgroundTasksScreen extends StatefulWidget {
  const BackgroundTasksScreen(
      {super.key, this.service, this.embedded = false, this.onCreate});
  final TaskService? service;
  final bool embedded;
  final VoidCallback? onCreate;
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
    final body = ListView(padding: const EdgeInsets.all(20), children: [
      Row(children: [
        Expanded(child: Text('Tasks', style: Stitch.title(30))),
        const StitchBadge('SAVED STATE'),
        IconButton(
            onPressed: refresh,
            tooltip: 'Refresh tasks',
            icon: const Icon(Icons.refresh, size: 18))
      ]),
      const SizedBox(height: 6),
      const Text('What Friday is working on autonomously.',
          style: TextStyle(color: Stitch.muted)),
      const SizedBox(height: 12),
      StitchCard(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            const Icon(Icons.memory, color: Stitch.cyan, size: 18),
            const SizedBox(width: 8),
            Expanded(
                child: Text(
                    '${tasks.where((t) => t['status'] == 'active').length} active gold checks · Android phone',
                    style: Stitch.mono(10)))
          ])),
      const SizedBox(height: 20),
      for (final t in tasks)
        Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: StitchCard(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Row(children: [
                    const Icon(Icons.currency_exchange, color: Stitch.cyan),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text('Gold ${t['direction']} ${t['threshold']}',
                            style: Stitch.title(19))),
                    StitchBadge('${t['status']}',
                        color: t['status'] == 'active'
                            ? Stitch.cyan
                            : Stitch.muted)
                  ]),
                  const SizedBox(height: 8),
                  Text('CHECK EVERY ${t['intervalMinutes']} MIN',
                      style: Stitch.mono(10)),
                  const SizedBox(height: 18),
                  _step('Saved quote check', Icons.data_usage,
                      'Reads Sona on this phone'),
                  _step('Compare threshold', Icons.balance,
                      'Quotes older than 5 minutes cannot trigger'),
                  _step('Last recorded outcome', Icons.receipt_long,
                      '${t['lastOutcome'] ?? 'Not checked'}'),
                  const SizedBox(height: 8),
                  Text('One-shot alert · no trades',
                      style: Stitch.mono(10, Stitch.green))
                ]))),
      if (tasks.isEmpty && data != null)
        StitchCard(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.checklist, color: Stitch.cyan, size: 30),
          const SizedBox(height: 12),
          Text('No saved gold tasks.', style: Stitch.title(20)),
          const SizedBox(height: 8),
          const Text(
              'Create a check from chat. Only saved quotes on this phone are used, not a live market API.')
        ])),
      const SizedBox(height: 22),
      Text('BACKGROUND EXECUTION', style: Stitch.mono(11)),
      const SizedBox(height: 8),
      StitchCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (data?['runtime'] != null)
          Text('Last recorded execution: ${data!['runtime']}'),
        if (data?['mode'] == 'unsupported')
          const Text(
              'These checks run on the Android phone, where Sona is installed.')
        else if (data != null)
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Battery saver'),
              subtitle: const Text(
                  'Off: checks about every requested interval. On: at least 15 minutes apart, possibly later.'),
              value: data?['mode'] == 'battery_saver',
              onChanged: (v) => change(service.setMode(v))),
        const SizedBox(height: 8),
        const Text(
            'Tasks survive closing Friday. Force-stopping stops checks until reopening. After reboot, checks use the slower worker until reopening.'),
        const SizedBox(height: 12),
        const Text(
            'Gold alerts read Sona\'s saved quotes on this phone. They do not fetch live prices or place trades. Quotes more than 5 minutes old cannot trigger an alert.')
      ])),
      const SizedBox(height: 18),
      const StitchCard(
          child: Text(
              'Try: "check gold every 5 minutes and tell me if it goes below 4150". Alerts are one-shot.')),
      if (error != null)
        Padding(
            padding: const EdgeInsets.all(12),
            child:
                Text(error!, style: const TextStyle(color: Color(0xFFFFB4AB)))),
      if (tasks.isNotEmpty)
        TextButton(
            onPressed: () => change(service.cancelAll()),
            child: const Text('Cancel all gold tasks')),
      const SizedBox(height: 16),
      FilledButton.icon(
          onPressed: widget.onCreate ?? () => Navigator.maybePop(context),
          icon: const Icon(Icons.add_task),
          label: const Text('Create a task in Chat'))
    ]);
    return widget.embedded
        ? body
        : Scaffold(
            appBar: const StitchHeader(title: 'Task Matrix', back: true),
            body: body);
  }

  Widget _step(String title, IconData icon, String detail) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 20, color: Stitch.cyan),
        const SizedBox(width: 12),
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(title),
              const SizedBox(height: 4),
              Text(detail, style: Stitch.mono(10))
            ]))
      ]));
}
