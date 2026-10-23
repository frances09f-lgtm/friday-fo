import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/device/reminder_service.dart';

/// The Alerts tab. Shows what Android allows for Friday's notifications and
/// gives one button for each thing that is switched off.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with WidgetsBindingObserver {
  static const channel = MethodChannel('friday/device');
  static const alerts = MethodChannel('friday/alerts');
  Map<String, dynamic>? state;
  String? result;
  List<String>? pending;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The tabs stay alive in an IndexedStack, so without this the screen kept
  /// showing "Disabled" after the user switched a setting on and came back.
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) refresh();
  }

  Future<bool> _readState() async {
    try {
      final s =
          await channel.invokeMapMethod<String, dynamic>('notificationState');
      if (mounted) setState(() => state = s);
      return true;
    } catch (_) {
      if (mounted) {
        setState(() => result =
            'Notification diagnostics are available on the Android phone.');
      }
      return false;
    }
  }

  Future<void> refresh() async {
    if (!await _readState()) return;
    try {
      final list = await ReminderService().pending();
      if (mounted) {
        setState(() => pending =
            list.map((r) => 'ID ${r.id}: ${r.title} - ${r.body}').toList());
      }
    } catch (_) {}
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
      if (mounted) {
        setState(
            () => result = 'The test failed before it could be submitted.');
      }
    }
    await refresh();
  }

  Future<void> _open(String method, String done,
      {MethodChannel via = alerts}) async {
    try {
      final ok = await via.invokeMethod<bool>(method);
      if (mounted) {
        setState(() => result = ok == false
            ? 'Android could not open that settings page. Open Settings > Apps > Friday instead.'
            : done);
      }
    } catch (_) {
      if (mounted) {
        setState(() => result =
            'Android could not open that settings page. Open Settings > Apps > Friday instead.');
      }
    }
  }

  Future<void> allowNotifications() async {
    final granted = await ReminderService().requestPermission();
    await _readState();
    if (granted || state?['enabled'] == true) {
      if (mounted) setState(() => result = 'Notifications are allowed.');
    } else {
      await _open('notificationSettings',
          via: channel,
          'Android did not show the permission box, so it is blocked for Friday. Turn Notifications on in the page that opened, then come back.');
    }
    await refresh();
  }

  String? get _phoneHint {
    final maker = '${state?['manufacturer'] ?? ''}'.toLowerCase();
    if (maker.contains('motorola') || maker.contains('moto')) {
      return 'Moto phone: also open Settings > Apps > Friday > Battery and choose Unrestricted. Menu names can differ by Android version.';
    }
    if (maker.contains('oneplus')) {
      return 'OnePlus phone: also open Settings > Battery > Battery optimization > Friday and choose Don\'t optimize, and allow auto-launch or background activity for Friday. Menu names can differ by OxygenOS version.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final s = state;
    final notificationsOff = s != null && s['enabled'] != true;
    final alarmsOff = s != null && s['exactAlarms'] != true;
    final batteryRestricted = s != null && s['batteryUnrestricted'] != true;
    final hint = _phoneHint;
    return Scaffold(
        appBar: AppBar(title: const Text('Notifications'), actions: [
          IconButton(onPressed: refresh, icon: const Icon(Icons.refresh))
        ]),
        body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                      'First test posting while Friday is open, then test a scheduled reminder. Neither button proves delivery until you see the notification.'),
                  const SizedBox(height: 12),
                  if (s != null) ...[
                    Text(
                        'App notifications: ${s['enabled'] == true ? 'Allowed' : 'Disabled'}'),
                    Text(
                        'Exact alarms: ${s['exactAlarms'] == true ? 'Allowed' : 'Not allowed; reminders may be late'}'),
                    Text(
                        'Battery optimization: ${s['batteryUnrestricted'] == true ? 'Unrestricted' : 'Restricted; background checks may be delayed'}'),
                    for (final c in (s['channels'] as List? ?? []).whereType<Map>())
                      Text(
                          '${c['name']}: ${c['enabled'] == true ? 'Allowed' : 'Disabled'}'),
                  ],
                  if (notificationsOff || alarmsOff || batteryRestricted) ...[
                    const SizedBox(height: 12),
                    const Text('Fix what is switched off'),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      if (notificationsOff)
                        FilledButton(
                            onPressed: allowNotifications,
                            child: const Text('Allow notifications')),
                      if (alarmsOff)
                        OutlinedButton(
                            onPressed: () => _open(
                                'exactAlarmSettings',
                                'Turn on Alarms & reminders for Friday, then come back.'),
                            child: const Text('Allow exact alarms')),
                      if (batteryRestricted)
                        OutlinedButton(
                            onPressed: () => _open(
                                'batterySettings',
                                'Choose Allow so Android stops limiting Friday in the background, then come back.'),
                            child: const Text('Remove battery limit')),
                    ]),
                  ],
                  if (hint != null) ...[
                    const SizedBox(height: 8),
                    Text(hint),
                  ],
                  const SizedBox(height: 12),
                  const Text('Pending reminders registered with Android'),
                  if (pending == null)
                    const Text('Pending list unavailable')
                  else if (pending!.isEmpty)
                    const Text('None recorded')
                  else
                    ...pending!.map(Text.new),
                  const SizedBox(height: 8),
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
                  TextButton(
                      onPressed: () => _open('autostartSettings',
                          'Allow Friday to start and run in the background there, then come back.'),
                      child: const Text('Open background / autostart settings')),
                  if (result != null)
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(result!)),
                  const Text(
                      'If the immediate test appears but the scheduled test does not, check alarms and battery settings. If neither appears, check app/channel permissions and Do Not Disturb. Do not clear app data; that removes saved tasks.'),
                ])));
  }
}
