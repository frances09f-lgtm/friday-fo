import 'package:flutter_test/flutter_test.dart';
import 'package:friday/services/oro/oro_bridge.dart';
import 'package:friday/services/ai/offline_engine.dart';

void main() {
  const snapshot = OroSnapshot(
      ts: 1000000,
      quoteAt: 1000000,
      accountAt: 400000,
      accountKnown: true,
      bid: 4002,
      ask: 4003,
      open: [
        OroPosition(dir: 'buy', qty: 2, entry: 4000, tp: 4010, sl: 3995),
        OroPosition(dir: 'sell', qty: 1, entry: 4004, tp: 3990, sl: 4010)
      ]);
  test('floating pnl uses executable bid for buys and ask for sells', () {
    final answer = OroBridge.answer('pnl', snapshot, nowMs: 1000000);
    expect(answer, contains('\$5.00'));
    expect(answer, contains('not realized'));
    expect(answer, contains('10 minutes ago'));
  });
  test('risk reports entry-stop estimate without pretending guaranteed fills',
      () {
    final answer = OroBridge.answer('risk', snapshot, nowMs: 1000000);
    expect(answer, contains('\$16.00'));
    expect(answer, contains('not guaranteed'));
  });
  test('multiple positions never silently picks the first for TP/SL', () {
    expect(OroBridge.answer('tpsl', snapshot, nowMs: 1000000),
        contains('cannot choose one'));
  });
  test('missing stops and unknown account are unknown, not zero', () {
    const incomplete = OroSnapshot(
        ts: 1,
        accountKnown: true,
        open: [OroPosition(dir: 'buy', entry: 4000, qty: 2)]);
    expect(OroBridge.answer('risk', incomplete), contains('unknown'));
    expect(OroBridge.answer('pnl', incomplete), contains('Not enough'));
    expect(
        OroBridge.answer('risk', const OroSnapshot(ts: 1, accountKnown: false)),
        contains('cannot tell'));
  });
  test('TP/SL distances are price points and source ages are separate', () {
    const single = OroSnapshot(
        ts: 1000000,
        quoteAt: 1000000,
        accountAt: 400000,
        accountKnown: true,
        bid: 4002,
        ask: 4003,
        open: [
          OroPosition(dir: 'buy', qty: 2, entry: 4000, tp: 4010, sl: 3995)
        ]);
    final answer = OroBridge.answer('distances', single, nowMs: 1000000);
    expect(answer, contains('8.00 price points'));
    expect(answer, contains('7.00 price points'));
    expect(answer, contains('not a prediction'));
  });
  test('offline routing preserves stop-loss vs losing distinction', () {
    const e = OfflineEngine();
    expect(e.handle('How much am I losing on my trade?').action.target, 'pnl');
    expect(e.handle('what is my stop loss?').action.target, 'tpsl');
    expect(e.handle('How far is my SL?').action.target, 'distances');
    expect(
        e.handle('How much am I risking on my trade?').action.target, 'risk');
  });
}
