import 'package:flutter_test/flutter_test.dart';
import 'package:friday/services/context/oro_context.dart';

void main() {
  test('follow-ups require recent Oro context and cannot mutate', () {
    final c = OroContext();
    final now = DateTime(2026, 10, 7, 22);
    expect(c.resolve('what about my trade?', now), isNull);
    c.remember(now);
    expect(c.resolve('what about my trade?', now), 'my open trades');
    expect(c.resolve("what's my TP?", now), 'my trade TP');
    expect(c.resolve('And SL?', now), 'my trade SL');
    expect(c.resolve('How much am I losing?', now), 'my trade profit loss');
    for (final s in [
      'yes',
      'do it',
      'close it',
      'buy',
      'send it',
      'change my SL',
      'set TP 4200'
    ]) {
      expect(c.resolve(s, now), isNull);
    }
    expect(c.resolve('and SL?', now.add(const Duration(minutes: 5))), isNull);
  });
  test('paired phone context retains target and clears after unrelated turn',
      () {
    final c = OroContext();
    final now = DateTime(2026, 10, 7, 22);
    c.remember(now, device: 'phone');
    expect(c.resolve('and SL?', now), 'my trade SL on my phone');
    c.clear();
    expect(c.resolve('and SL?', now), isNull);
  });
}
