import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friday/services/device/reminder_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'overlay Activity permission error does not invalidate initialized scheduler',
      () async {
    final calls = <String>[];
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'initialize':
          return true;
        case 'requestNotificationsPermission':
          throw PlatformException(code: 'no_activity');
        case 'areNotificationsEnabled':
          return true;
        case 'canScheduleExactNotifications':
          return false;
        case 'requestExactAlarmsPermission':
          throw PlatformException(code: 'no_activity');
        case 'pendingNotificationRequests':
          return [];
        default:
          return true;
      }
    });
    // Static test complements Android compilation: no real alarm claimed here.
    final service = ReminderService();
    await service.init();
    await service.pending();
    expect(calls.where((x) => x == 'initialize').length, 1);
    expect(calls, contains('pendingNotificationRequests'));
  });
}
