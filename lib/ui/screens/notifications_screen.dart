import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/device/reminder_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  static const channel = MethodChannel('friday/device');
  Map<String, dynamic>? state;
  String? result;
  List<String>? pending;
  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    try {
      final s =
          await channel.invokeMapMethod<String, dynamic>('notificationState');
      if (mounted) setState(() => state = s);
      final list = await ReminderService().pending();
      if (mounted)
        setState(() {
          state = s;
          pending =
              list.map((r) => 'ID ${r.id}: ${r.title} - ${r.body}').toList();
        });
    } catch (_) {
      if (mounted)
        setState(() => result =
            'Notification diagnostics are available on the Android phone.');
    }
  }

  Future<void> test(bool scheduled) async {
    try {
      final r = scheduled
          ? (await ReminderService().schedule(
                  title: 'One-minute test',
                  body:
                      'Scheduled reminder test. Compare this with the immediate test.',
                  after: const Duration(minutes: 1))
              ? 'One-minute reminder registered with Android. Check the notification shade after a minute; battery restrictions can delay it.'
              : 'Could not register the reminder. Check notification settings.')
          : await channel.invokeMethod<String>('notificationTest');
      if (mounted) setState(() => result = r);
    } catch (_) {
      if (mounted)
        setState(
            () => result = 'The test failed before it could be submitted.');
    }
    await refresh();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Notifications'), actions: [
        IconButton(onPressed: refresh, icon: const Icon(Icons.refresh))
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text(
            'First test posting while Friday is open, then test a scheduled reminder. Neither button proves delivery until you see the notification.'),
        const SizedBox(height: 12),
        if (state != null) ...[
          Text(
              'App notifications: ${state!['enabled'] == true ? 'Allowed' : 'Disabled'}'),
          Text(
              'Exact alarms: ${state!['exactAlarms'] == true ? 'Allowed' : 'Not allowed; reminders may be late'}'),
          Text(
              'Battery optimization: ${state!['batteryUnrestricted'] == true ? 'Unrestricted' : 'Restricted; background checks may be delayed'}'),
          for (final c in (state!['channels'] as List? ?? []).whereType<Map>())
            Text(
                '${c['name']}: ${c['enabled'] == true ? 'Allowed' : 'Disabled'}'),
        ],
        const SizedBox(height: 12),
        const Text('Pending reminders registered with Android'),
        if (pending == null)
          const Text('Pending list unavailable')
        else if (pending!.isEmpty)
          const Text('None recorded')
        else
          ...pending!.map(Text.new),
        FilledButton(
            onPressed: () => test(false),
            child: const Text('Test notification now')),
        OutlinedButton(
            onPressed: () => test(true),
            child: const Text('Test reminder in 1 minute')),
        TextButton(
            onPressed: () async {
              try {
                await channel.invokeMethod('notificationSettings');
              } catch (_) {}
            },
            child: const Text('Open notification settings')),
        if (result != null)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(result!)),
        const Text(
            'If the immediate test appears but the scheduled test does not, check alarms and battery settings. If neither appears, check app/channel permissions and Do Not Disturb. Do not clear app data; that removes saved tasks.'),
      ]));
}
