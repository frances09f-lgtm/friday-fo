import 'package:flutter_test/flutter_test.dart';
import 'package:friday/services/ai/offline_engine.dart';
import 'package:friday/models/friday_response.dart';
import 'package:friday/services/device/reminder_service.dart';

void main() {
  test('notification ids are clock-derived and unique across sessions', () {
    final a = ReminderService.newNotificationId(1760000000000);
    final b = ReminderService.newNotificationId(1760000001000);
    expect(a, isNot(b));
    expect(a, greaterThan(0));
  });

  test('remind me at 7:30 pm computes minutes ahead', () {
    final r = const OfflineEngine().handle('remind me to call mom at 7:30 pm');
    expect(r.action.type, FridayActionType.setReminder);
    expect(r.action.title, 'call mom');
    expect(r.action.afterMinutes, greaterThan(0));
  });

  test('remind me in 2 hours converts to minutes', () {
    final r = const OfflineEngine().handle('remind me to drink water in 2 hours');
    expect(r.action.type, FridayActionType.setReminder);
    expect(r.action.afterMinutes, 120);
  });
}
