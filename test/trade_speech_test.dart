import 'package:flutter_test/flutter_test.dart';
import 'package:friday/services/ai/offline_engine.dart';
import 'package:friday/models/friday_response.dart';
import 'package:friday/services/oro/oro_bridge.dart';
import 'package:friday/services/device/device_hub.dart';

class SavedHub extends DeviceHub {
  String? raw;
  @override
  Future<String?> oroStatusRaw() async => raw;
}

void main() {
  test('explicit open trade speech always deterministic bridge', () {
    for (final s in [
      'check my open trades',
      'open trades',
      'open traits',
      'check my open traits',
      'check open tradez',
      "check my open trade's"
    ]) {
      final a = const OfflineEngine().handle(s).action;
      expect(a.type, FridayActionType.oroStatus, reason: s);
      expect(a.target, 'trades');
    }
    expect(const OfflineEngine().handle('my personality traits').action.type,
        isNot(FridayActionType.oroStatus));
  });
  test('bridge returns real saved list or honest absence, not acknowledgment',
      () async {
    final h = SavedHub();
    final a = const OfflineEngine().handle('check my open traits').action;
    expect(OroBridge.answer(a.target, await OroBridge(h).read()),
        contains("couldn't read"));
    h.raw =
        '{"quoteAt":1,"updatedAt":1,"balance":12,"accountKnown":true,"open":[{"dir":"buy","qty":1,"entry":4119.97,"tp":4125,"sl":4110}]}';
    final answer = OroBridge.answer(a.target, await OroBridge(h).read());
    expect(answer, isNot(contains('Sure')));
    expect(answer, contains('1 open trade: buy 1 oz at 4,120.0'));
  });
}
