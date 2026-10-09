import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Schedules reminder notifications. flutter_local_notifications + timezone
/// handle exact alarms; see README for the SCHEDULE_EXACT_ALARM note.
class ReminderService {
  ReminderService();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  int? lastRegisteredId;
  DateTime? lastRegisteredAt;
  Future<List<PendingNotificationRequest>> pending() async {
    await init();
    if (!_initialized) return [];
    return _plugin.pendingNotificationRequests();
  }

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
    const androidInit = AndroidInitializationSettings('ic_friday_notification');
    try {
      await _plugin.initialize(
        const InitializationSettings(android: androidInit),
      );
      // Android 13+ starts with notifications denied - ask once at startup,
      // otherwise scheduled reminders fire with nothing visible.
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      // A service-hosted overlay has no Activity for a permission dialog.
      // Plugin initialization is valid regardless; don't discard it if the
      // permission request throws. schedule checks the actual grant below.
      _initialized = true;
      try {
        await android?.requestNotificationsPermission();
      } catch (_) {}
    } catch (_) {
      _initialized = false;
    }
  }

  Future<bool> schedule({
    required String title,
    required String body,
    required Duration after,
  }) async {
    await init();
    if (!_initialized) return false;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (await android?.areNotificationsEnabled() != true) return false;
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
      final id = newNotificationId(DateTime.now().millisecondsSinceEpoch);
      await _plugin.zonedSchedule(
        id,
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
      final requests = await _plugin.pendingNotificationRequests();
      if (!requests.any((r) => r.id == id)) return false;
      lastRegisteredId = id;
      lastRegisteredAt = when;
      return true;
    } catch (_) {
      return false;
    }
  }
}
