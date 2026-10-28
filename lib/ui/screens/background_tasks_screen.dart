import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/tasks/task_service.dart';
import '../stitch_style.dart';
import '../friday_motion.dart';
class BackgroundTasksScreen extends StatefulWidget {
  const BackgroundTasksScreen({super.key, this.service, this.embedded = false, this.onCreate});
  final TaskService? service;
  final bool embedded;
  final VoidCallback? onCreate;
  static const refreshEvery = Duration(seconds: 20);
  @override
  State<BackgroundTasksScreen> createState() => _BackgroundTasksScreenState();
}
class _BackgroundTasksScreenState extends State<BackgroundTasksScreen> with WidgetsBindingObserver {
  late final TaskService service = widget.service ?? TaskService();
  Map<String, dynamic>? data;
  String? error;
  Timer? _poll;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    refresh();
    // Tasks finish in the background (an alert fires); re-read so finished
    // ones drop off this page without leaving it.
    _poll = Timer.periodic(BackgroundTasksScreen.refreshEvery, (_) => refresh());
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }
  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  Future<void> refresh() async {
    try { final value = await service.state(); if (mounted) setState(() { data = value; error = null; }); }
    catch (_) { if (mounted) setState(() => error = 'Could not read saved background tasks.'); }
  }
  Future<void> change(Future<String> operation) async {
    try { final result = await operation; if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result))); }
    catch (_) { if (mounted) setState(() => error = 'Could not change background tasks.'); }
    await refresh();
  }
  /// Asks before removing; removing stops the task's checks for good.
  Future<bool> confirmRemove(Map t) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Remove this task?'),
      content: Text('Gold ${t['direction']} ${t['threshold']} stops checking and will not come back. No alert will be sent for it.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
        TextButton(key: const ValueKey('confirm-remove-task'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
      ]));
    return ok == true;
  }
  Future<bool> confirmRemoveAll() async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Remove all tasks?'),
      content: const Text('Every gold check stops and is removed from this phone.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
        TextButton(key: const ValueKey('confirm-remove-all'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove all')),
      ]));
    return ok == true;
  }
  /// Takes the task off the page at once, then has the phone stop and delete it.
  Future<void> remove(Map t) async {
    setState(() => data = withoutTask(data, t));
    try {
      final result = await service.cancel(t);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result)));
    } catch (_) { if (mounted) setState(() => error = 'Could not remove the task.'); }
    await refresh();
  }
  Future<void> askRemove(Map t) async { if (await confirmRemove(t) && mounted) await remove(t); }
  Future<void> askRemoveAll() async { if (await confirmRemoveAll() && mounted) await change(service.cancelAll()); }
  @override
  Widget build(BuildContext context) {
    final tasks = openTasks(data);
    final body = MotionList(padding: const EdgeInsets.all(20), children: [
      Row(children: [Expanded(child: Text('Tasks', style: Stitch.title(30))), const StitchBadge('SAVED STATE'),
        MotionPress(scale: .88, child: IconButton(onPressed: refresh, tooltip: 'Refresh tasks', icon: const Icon(Icons.refresh, size: 18))),
        PopupMenuButton<String>(key: const ValueKey('tasks-menu'), tooltip: 'Task options', icon: const Icon(Icons.more_vert, size: 18),
          onSelected: (v) { if (v == 'remove_all') askRemoveAll(); },
          itemBuilder: (_) => [PopupMenuItem(value: 'remove_all', enabled: tasks.isNotEmpty, child: const Text('Remove all tasks'))])]),
      const SizedBox(height: 6), const Text('What Friday is working on autonomously.', style: TextStyle(color: Stitch.muted)), const SizedBox(height: 12),
      StitchCard(padding: const EdgeInsets.all(12), child: Row(children: [const Icon(Icons.memory, color: Stitch.cyan, size: 18), const SizedBox(width: 8),
        Expanded(child: Text('${tasks.where((t) => t['status'] == 'active').length} active gold checks · Android phone', style: Stitch.mono(10)))])),
      const SizedBox(height: 20),
      for (final t in tasks) Dismissible(key: ValueKey('task-${taskKey(t)}'), direction: DismissDirection.endToStart,
        confirmDismiss: (_) => confirmRemove(t), onDismissed: (_) => remove(t),
        background: Padding(padding: const EdgeInsets.only(bottom: 16), child: DecoratedBox(
          decoration: BoxDecoration(color: const Color(0x33FFB4AB), borderRadius: BorderRadius.circular(20)),
          child: const Align(alignment: Alignment.centerRight, child: Padding(padding: EdgeInsets.only(right: 24),
            child: Row(mainAxisSize: MainAxisSize.min, children: [Text('Remove', style: TextStyle(color: Color(0xFFFFB4AB))), SizedBox(width: 8),
              Icon(Icons.delete_outline, color: Color(0xFFFFB4AB))]))))),
        child: Padding(padding: const EdgeInsets.only(bottom: 16),
        child: GestureDetector(onLongPress: () => askRemove(t), child: StitchCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [const Icon(Icons.currency_exchange, color: Stitch.cyan), const SizedBox(width: 10),
            Expanded(child: Text('Gold ${t['direction']} ${t['threshold']}', style: Stitch.title(19))),
            StitchBadge('${t['status']}', color: t['status'] == 'active' ? Stitch.cyan : Stitch.muted),
            SizedBox(width: 32, height: 32, child: PopupMenuButton<String>(key: ValueKey('task-menu-${taskKey(t)}'), tooltip: 'Task options', padding: EdgeInsets.zero,
              icon: const Icon(Icons.more_vert, size: 18, color: Stitch.muted),
              onSelected: (v) { if (v == 'remove') askRemove(t); },
              itemBuilder: (_) => const [PopupMenuItem(value: 'remove', child: Row(children: [Icon(Icons.delete_outline, size: 18), SizedBox(width: 10), Text('Remove task')]))]))]),
          const SizedBox(height: 8), Text('CHECK EVERY ${t['intervalMinutes']} MIN', style: Stitch.mono(10)), const SizedBox(height: 18),
          _step('Saved quote check', Icons.data_usage, 'Reads Sona on this phone'),
          _step('Compare threshold', Icons.balance, 'Quotes older than 5 minutes cannot trigger'),
          _step('Last recorded outcome', Icons.receipt_long, '${t['lastOutcome'] ?? 'Not checked'}'), const SizedBox(height: 8),
          Text('One-shot alert · no trades · swipe to remove', style: Stitch.mono(10, Stitch.green))
        ]))))),
      if (tasks.isEmpty && data != null) StitchCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.checklist, color: Stitch.cyan, size: 30), const SizedBox(height: 12), Text('No active tasks.', style: Stitch.title(20)), const SizedBox(height: 8),
        const Text('Finished tasks clear from here on their own. Create a check from chat. Only saved quotes on this phone are used, not a live market API.')
      ])),
      const SizedBox(height: 22), Text('BACKGROUND EXECUTION', style: Stitch.mono(11)), const SizedBox(height: 8),
      StitchCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (data?['runtime'] != null) Text('Last recorded execution: ${data!['runtime']}'),
        if (data?['mode'] == 'unsupported') const Text('These checks run on the Android phone, where Sona is installed.')
        else if (data != null) MotionSwitchTile(contentPadding: EdgeInsets.zero, title: const Text('Battery saver'),
          subtitle: const Text('Off: checks about every requested interval. On: at least 15 minutes apart, possibly later.'),
          value: data?['mode'] == 'battery_saver', onChanged: (v) => change(service.setMode(v))),
        const SizedBox(height: 8), const Text('Tasks survive closing Friday. Force-stopping stops checks until reopening. After reboot, checks use the slower worker until reopening.'), const SizedBox(height: 12),
        const Text('Gold alerts read Sona\'s saved quotes on this phone. They do not fetch live prices or place trades. Quotes more than 5 minutes old cannot trigger an alert.')
      ])),
      const SizedBox(height: 18), const StitchCard(child: Text('Try: "check gold every 5 minutes and tell me if it goes below 4150". Alerts are one-shot.')),
      if (error != null) Padding(padding: const EdgeInsets.all(12), child: Text(error!, style: const TextStyle(color: Color(0xFFFFB4AB)))),
      if (tasks.isNotEmpty) MotionPress(child: TextButton(onPressed: askRemoveAll, child: const Text('Remove all tasks'))), const SizedBox(height: 16),
      MotionPress(child: FilledButton.icon(onPressed: widget.onCreate ?? () => Navigator.maybePop(context), icon: const Icon(Icons.add_task), label: const Text('Create a task in Chat')))
    ]);
    return widget.embedded ? body : Scaffold(appBar: const StitchHeader(title: 'Task Matrix', back: true), body: body);
  }
  Widget _step(String title, IconData icon, String detail) => Padding(padding: const EdgeInsets.only(bottom: 14), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Icon(icon, size: 20, color: Stitch.cyan), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title), const SizedBox(height: 4), Text(detail, style: Stitch.mono(10))]))
  ]));
}
