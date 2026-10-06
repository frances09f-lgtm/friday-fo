import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Schedules reminder notifications. flutter_local_notifications + timezone
/// handle exact alarms; see README for the SCHEDULE_EXACT_ALARM note.
class ReminderService {
  ReminderService();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  int _nextId = 1;

  Future<void> init() async {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
    } catch (_) {}
    const androidInit = AndroidInitializationSettings('ic_launcher');
    await _plugin.initialize(
      const InitializationSettings(android: androidInit),
    );
    _initialized = true;
  }

  Future<bool> schedule({
    required String title,
    required String body,
    required Duration after,
  }) async {
    await init();
    try {
      final when = tz.TZDateTime.now(tz.local).add(after);
      await _plugin.zonedSchedule(
        _nextId++,
        title.isEmpty ? 'Reminder' : 'Friday: $title',
        body,
        when,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'friday_reminders',
            'Friday reminders',
            channelDescription: 'Reminders Friday schedules for you',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
