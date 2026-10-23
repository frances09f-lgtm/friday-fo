import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friday/ui/screens/notifications_screen.dart';
import 'dart:io';

void main() {
  const channel = MethodChannel('friday/device');
  const alerts = MethodChannel('friday/alerts');
  const plugin = MethodChannel('dexterous.com/flutter/local_notifications');

  testWidgets('alerts tab re-reads state on resume and fix buttons open Android',
      (t) async {
    final calls = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (c) async {
      calls.add(c.method);
      if (c.method == 'notificationState') {
        return {
          'enabled': false,
          'exactAlarms': false,
          'batteryUnrestricted': false,
          'manufacturer': 'motorola',
          'channels': [
            {'name': 'Friday reminders', 'enabled': true},
          ]
        };
      }
      return true;
    });
    messenger.setMockMethodCallHandler(alerts, (c) async {
      calls.add('alerts:${c.method}');
      return true;
    });
    // The local notifications plugin has no Android side in a unit test.
    // Answer "not granted" so the screen falls back to the settings page.
    messenger.setMockMethodCallHandler(plugin, (c) async {
      if (c.method == 'initialize') return true;
      if (c.method == 'requestNotificationsPermission') return false;
      return null;
    });
    await t.binding.setSurfaceSize(const Size(412, 915));
    await t.pumpWidget(const MaterialApp(home: NotificationsScreen()));
    await t.pumpAndSettle();
    expect(find.text('Allow notifications'), findsOneWidget);
    expect(find.text('Allow exact alarms'), findsOneWidget);
    expect(find.text('Remove battery limit'), findsOneWidget);
    expect(find.textContaining('Moto phone'), findsOneWidget);

    final before = calls.where((m) => m == 'notificationState').length;
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();
    expect(calls.where((m) => m == 'notificationState').length,
        greaterThan(before));

    await t.ensureVisible(find.text('Remove battery limit'));
    await t.tap(find.text('Remove battery limit'));
    await t.pumpAndSettle();
    expect(calls, contains('alerts:batterySettings'));

    await t.ensureVisible(find.text('Allow exact alarms'));
    await t.tap(find.text('Allow exact alarms'));
    await t.pumpAndSettle();
    expect(calls, contains('alerts:exactAlarmSettings'));

    await t.ensureVisible(find.text('Open background / autostart settings'));
    await t.tap(find.text('Open background / autostart settings'));
    await t.pumpAndSettle();
    expect(calls, contains('alerts:autostartSettings'));

    await t.ensureVisible(find.text('Allow notifications'));
    await t.tap(find.text('Allow notifications'));
    await t.pumpAndSettle();
    // Permission not granted, so the app sends the user to the Android
    // notification page instead.
    expect(calls, contains('notificationSettings'));
    expect(t.takeException(), isNull);

    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(alerts, null);
    messenger.setMockMethodCallHandler(plugin, null);
  });

  test('alert plumbing is declared in the Android project', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('android.permission.POST_NOTIFICATIONS'));
    expect(manifest, contains('android.permission.SCHEDULE_EXACT_ALARM'));
    expect(
        File('android/app/src/release/AndroidManifest.xml')
            .readAsStringSync(),
        contains('android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS'));
    final health = File(
            'android/app/src/main/kotlin/com/friday/assistant/NotificationHealth.kt')
        .readAsStringSync();
    expect(health, contains('fun ensureChannels'));
    expect(health, contains('"friday_gold_alerts"'));
    final main = File(
            'android/app/src/main/kotlin/com/friday/assistant/MainActivity.kt')
        .readAsStringSync();
    for (final m in ['exactAlarmSettings', 'batterySettings', 'autostartSettings']) {
      expect(main, contains('"$m"'));
    }
    expect(main, contains('NotificationHealth.ensureChannels(this)'));
  });
}
