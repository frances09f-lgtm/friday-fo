import 'package:flutter_test/flutter_test.dart';
import 'package:friday/services/tasks/gold_task.dart';

void main() {
  test('exact supported gold tasks parse without a cloud model', () {
    final r = GoldTaskRequest.parse(
        'Check gold every 5 minutes and tell me if it goes below 4150');
    expect(r?.threshold, 4150);
    expect(r?.intervalMinutes, 5);
    expect(r?.direction, 'below');
    expect(
        GoldTaskRequest.parse(
                'check gold every hour and notify me when gold rises above 4200')
            ?.intervalMinutes,
        60);
    expect(
        GoldTaskRequest.parse(
                'check gold every 2 hours and alert me if it is below 4150.5')
            ?.threshold,
        4150.5);
  });
  test('does not reinterpret generic web, trade or invalid requests', () {
    for (final s in [
      'check this every hour',
      'notify me if my trade reaches TP',
      'check gold every 1 minute and tell me if it goes below 4150',
      'check gold every 999 hours and tell me if it goes below 4150',
      'check gold every 5 minutes and tell me if it goes below 0',
      'check silver every hour and tell me if it goes below 40'
    ]) {
      expect(GoldTaskRequest.parse(s), isNull, reason: s);
    }
  });
}
