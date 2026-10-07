import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:friday/services/device/reminder_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  test('manifest has posting receiver and notification icon is drawable', () {
    final m =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(
        m,
        contains(
            'com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver'));
    expect(
        File('android/app/src/main/res/drawable/ic_friday_notification.xml')
            .existsSync(),
        true);
  });
  test('failed initialize can retry and cannot claim scheduled success',
      () async {
    var attempts = 0, scheduled = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (c) async {
      if (c.method == 'initialize') {
        attempts++;
        throw PlatformException(code: 'invalid_icon');
      }
      if (c.method == 'zonedSchedule') scheduled++;
      return true;
    });
    final s = ReminderService();
    expect(
        await s.schedule(
            title: 'x', body: 'y', after: const Duration(minutes: 1)),
        false);
    expect(
        await s.schedule(
            title: 'x', body: 'y', after: const Duration(minutes: 1)),
        false);
    expect(attempts, 2);
    expect(scheduled, 0);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  test('denied notification permission does not register invisible reminder',
      () async {
    var scheduled = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (c) async {
      if (c.method == 'areNotificationsEnabled') return false;
      if (c.method == 'zonedSchedule') scheduled++;
      return true;
    });
    expect(
        await ReminderService()
            .schedule(title: 'x', body: 'y', after: const Duration(minutes: 1)),
        false);
    expect(scheduled, 0);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
}
