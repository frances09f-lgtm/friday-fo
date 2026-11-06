import 'package:flutter_test/flutter_test.dart';
import 'package:friday/services/context/price_subject_context.dart';

void main() {
  test('bounded subject substitution keeps all supplied alert parameters', () {
    final c = PriceSubjectContext();
    final now = DateTime(2026, 11, 6, 9, 28);
    const text = 'tell me when it goes below 3920 every 15 minutes';
    expect(c.resolve(text, now), isNull);
    c.remember('gold', now);
    expect(c.resolve(text, now),
        'tell me when gold goes below 3920 every 15 minutes');
    expect(c.resolve('alert me when the price reaches 4200', now),
        'alert me when gold reaches 4200');
    for (final t in [
      'buy it 0.1 lot',
      'close it',
      'tell me when silver goes above 40',
      'tell me when platinum price goes above 3000',
      'send it to John',
      'tell me when battery goes above 50',
      'tell me when gold goes below 3000'
    ]) {
      expect(c.resolve(t, now), isNull, reason: t);
    }
    expect(c.resolve(text, now.add(const Duration(minutes: 5))), isNull);
    expect(c.resolve(text, now.subtract(const Duration(seconds: 1))), isNull);
    c.clear();
    expect(c.resolve(text, now), isNull);
  });
}
