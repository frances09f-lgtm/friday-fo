import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Schedules reminder notifications. flutter_local_notifications + timezone
/// handle exact alarms; see README for the SCHEDULE_EXACT_ALARM note.
class ReminderService {
  ReminderService();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// Notification IDs come from the clock, not a counter: a counter resets
  /// every process start, so two reminders set in different app sessions
  /// collided on id=1 and the newer one silently replaced the older.
  static int newNotificationId(int millisSinceEpoch) =>
      millisSinceEpoch % 0x7FFFFFFF;

  Future<void> init() async {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
    } catch (_) {}
    const androidInit = AndroidInitializationSettings('ic_launcher');
    try {
      await _plugin.initialize(
        const InitializationSettings(android: androidInit),
      );
      // Android 13+ starts with notifications denied - ask once at startup,
      // otherwise scheduled reminders fire with nothing visible.
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
    } catch (_) {
      // Notifications unavailable on this device - reminders just won't fire.
    }
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
      // Exact alarms need SCHEDULE_EXACT_ALARM - on Android 13+ it starts
      // denied. Ask once; if still denied, fall back to inexact so the
      // reminder still fires (possibly a few minutes late) instead of
      // silently failing.
      var mode = AndroidScheduleMode.exactAllowWhileIdle;
      try {
        final android = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        var canExact = await android?.canScheduleExactNotifications() ?? false;
        if (!canExact) {
          await android?.requestExactAlarmsPermission();
          canExact = await android?.canScheduleExactNotifications() ?? false;
        }
        if (!canExact) mode = AndroidScheduleMode.inexactAllowWhileIdle;
      } catch (_) {
        mode = AndroidScheduleMode.inexactAllowWhileIdle;
      }
      await _plugin.zonedSchedule(
        newNotificationId(DateTime.now().millisecondsSinceEpoch),
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
        androidScheduleMode: mode,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
