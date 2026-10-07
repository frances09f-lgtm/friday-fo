import 'package:flutter_test/flutter_test.dart';
import 'package:friday/models/friday_response.dart';
import 'package:friday/services/ai/offline_engine.dart';
import 'package:friday/services/oro/oro_bridge.dart';

void main() {
  const engine = OfflineEngine();

  FridayAction actionOf(String text) {
    final r = engine.handle(text);
    return r.action;
  }

  group('Oro routing (user project: connect the apps, offline-first)', () {
    test('gold price questions route to the bridge', () {
      for (final q in [
        'current gold price',
        'what is the gold price',
        'gold rate today',
        'price of gold',
      ]) {
        final a = actionOf(q);
        expect(a.type, FridayActionType.oroStatus, reason: q);
        expect(a.target, 'price', reason: q);
      }
    });

    test('open trades questions route to the bridge', () {
      for (final q in [
        'my open trades',
        'any open positions',
        'show current trades',
        'what trades are open',
      ]) {
        final a = actionOf(q);
        expect(a.type, FridayActionType.oroStatus, reason: q);
        expect(a.target, 'trades', reason: q);
      }
    });

    test('TP/SL questions route to the bridge', () {
      for (final q in [
        "what's my tp",
        'what is my TP',
        'my stop loss',
        'take profit for my trade',
      ]) {
        final a = actionOf(q);
        expect(a.type, FridayActionType.oroStatus, reason: q);
        expect(a.target, 'tpsl', reason: q);
      }
    });

    test('paper balance questions route to the bridge', () {
      final a = actionOf('what is my paper balance');
      expect(a.type, FridayActionType.oroStatus);
      expect(a.target, 'balance');
    });

    test('ordinary commands are not swallowed by Oro routing', () {
      expect(actionOf('open camera').type, FridayActionType.openApp);
      expect(actionOf('read my messages').type, FridayActionType.readMessages);
      expect(actionOf('volume up').type, FridayActionType.volumeUp);
    });
  });

  group('close all apps (user voice ask)', () {
    test('close-all phrasings route to closeAllApps', () {
      for (final q in [
        'close all apps',
        'close all background apps',
        'clear all apps',
        'kill background apps',
        'close everything',
      ]) {
        expect(actionOf(q).type, FridayActionType.closeAllApps, reason: q);
      }
    });

    test('closing ONE app is not close-all', () {
      expect(actionOf('close chrome').type, isNot(FridayActionType.closeAllApps));
    });
  });

  group('OroBridge answers (real data only, age disclosed)', () {
    final now = 2000000000000; // fixed clock for age wording
    OroSnapshot snap({
      double? bid,
      double? ask,
      int quoteAt = 0,
      double? balance,
      List<OroPosition> open = const [],
      int ts = 0,
    }) =>
        OroSnapshot(
          ts: ts,
          bid: bid,
          ask: ask,
          quoteAt: quoteAt,
          balance: balance,
          open: open,
        );

    test('no snapshot: honest, no invented numbers', () {
      final a = OroBridge.answer('price', null, nowMs: now);
      expect(a, contains("couldn't read Oro"));
      expect(a, isNot(contains(RegExp(r'\d,\d{3}'))));
    });

    test('price from real quote with age', () {
      final s = snap(
          bid: 4123.0, ask: 4123.8, quoteAt: now - 3 * 60 * 1000);
      final a = OroBridge.answer('price', s, nowMs: now);
      expect(a, contains('4,123.4'));
      expect(a, contains('3 minutes ago'));
    });

    test('fresh quote says just now', () {
      final s = snap(bid: 4000.0, ask: 4000.4, quoteAt: now - 10 * 1000);
      expect(OroBridge.answer('price', s, nowMs: now), contains('just now'));
    });

    test('no quote yet: says so instead of inventing one', () {
      final s = snap(quoteAt: 0, ts: now);
      expect(OroBridge.answer('price', s, nowMs: now),
          contains("hasn't seen a live gold price"));
    });

    test('no open trades: says so', () {
      final s = snap(bid: 1, ask: 1, quoteAt: now);
      expect(OroBridge.answer('trades', s, nowMs: now),
          contains('No open trades'));
    });

    test('open trade described with TP/SL and floating P/L', () {
      final s = snap(
        bid: 4124.0,
        ask: 4124.5,
        quoteAt: now,
        open: [
          const OroPosition(dir: 'buy', qty: 1.5, entry: 4119.7, tp: 4125.0, sl: 4117.0),
        ],
      );
      final a = OroBridge.answer('trades', s, nowMs: now);
      expect(a, contains('1 open trade'));
      expect(a, contains('buy 1.5 oz at 4,119.7'));
      expect(a, contains('TP 4,125.0'));
      expect(a, contains('SL 4,117.0'));
      expect(a, contains('up \$6.45')); // (4124.0-4119.7)*1.5
    });

    test('tpsl with no open trade is honest', () {
      final s = snap(quoteAt: now);
      expect(OroBridge.answer('tpsl', s, nowMs: now),
          contains('no TP or SL'));
    });

    test('tpsl answers from the open position', () {
      final s = snap(
        quoteAt: now,
        open: [const OroPosition(dir: 'sell', qty: 2, entry: 4100, tp: 4090, sl: 4110)],
      );
      final a = OroBridge.answer('tpsl', s, nowMs: now);
      expect(a, contains('TP 4,090.0'));
      expect(a, contains('SL 4,110.0'));
    });

    test('balance formatting', () {
      final s = snap(quoteAt: now, balance: 9982.3);
      final a = OroBridge.answer('balance', s, nowMs: now);
      expect(a, contains('\$9,982.30'));
    });

    test('snapshot json round-trips', () {
      const raw =
          '{"ts":1,"bid":4123.0,"ask":4123.8,"quoteAt":2,"balance":9982.3,'
          '"open":[{"dir":"buy","qty":1.5,"entry":4119.7,"tp":4125,"sl":4117}]}';
      final s = OroSnapshot.parse(raw)!;
      expect(s.bid, 4123.0);
      expect(s.open.single.tp, 4125);
      expect(s.open.single.qty, 1.5);
    });

    test('garbage json yields null, not a crash', () {
      expect(OroSnapshot.parse('not json'), isNull);
    });
  });
}
