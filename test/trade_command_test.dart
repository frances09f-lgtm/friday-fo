import 'package:flutter_test/flutter_test.dart';
import 'package:friday/services/oro/trade_command.dart';

TradeCommand cmd(String s) {
  final p = TradeCommandParser.parse(s);
  expect(p, isNotNull, reason: s);
  expect(p!.command, isNotNull, reason: '$s -> ${p.question}');
  return p.command!;
}

String question(String s) {
  final p = TradeCommandParser.parse(s);
  expect(p, isNotNull, reason: s);
  expect(p!.command, isNull, reason: s);
  return p.question!;
}

void main() {
  group('open orders', () {
    test('buy gold 0.1 lot', () {
      final c = cmd('buy gold 0.1 lot');
      expect(c.op, TradeOp.open);
      expect(c.side, 'buy');
      expect(c.lots, 0.1);
      expect(c.oz, 10);
      expect(c.tp, isNull);
      expect(c.sl, isNull);
    });
    test('sell with SL and TP in any order and spelling', () {
      for (final s in [
        'sell 0.05 with SL 2310 TP 2280',
        'Sell 0.05 lot, TP 2280, SL 2310.',
        'sell gold 0.05 lots stop loss 2310 take profit 2280',
        'sell xauusd 0.05 s/l 2310 t/p 2280',
        'please sell 5 oz of gold with sl at 2310 and tp at 2280',
        'short gold 0.05 lot sl 2310 target 2280',
      ]) {
        final c = cmd(s);
        expect(c.side, 'sell', reason: s);
        expect(c.lots, 0.05, reason: s);
        expect(c.sl, 2310, reason: s);
        expect(c.tp, 2280, reason: s);
      }
    });
    test('bare size and oz units', () {
      expect(cmd('buy 0.1').lots, 0.1);
      expect(cmd('buy 1 gold').lots, 1);
      expect(cmd('buy 10 oz gold').lots, 0.1);
      expect(cmd('Friday, can you buy gold 0.02 lot at market').lots, 0.02);
      expect(cmd('open a buy trade 0.01 lot').lots, 0.01);
      expect(cmd('go long gold 0.3 lot').side, 'buy');
      expect(cmd('buy XAU/USD 0.1lot').lots, 0.1);
    });
    test('missing size asks and keeps a draft', () {
      final p = TradeCommandParser.parse('buy gold')!;
      expect(p.command, isNull);
      expect(p.question, contains('How much'));
      expect(p.draft!.side, 'buy');
      final q = TradeCommandParser.parse('sell gold sl 4150 tp 4080')!;
      expect(q.draft!.sl, 4150);
      expect(q.draft!.tp, 4080);
      expect(TradeCommandParser.parse('sell')!.draft!.side, 'sell');
    });
    test('vague trade intents ask for the size (gold is implied)', () {
      for (final s in [
        'buy a trade', 'Buy a trade.', 'buy', 'buy gold', 'buy a new trade',
        'buy a position', 'go long', 'buy a paper trade please',
      ]) {
        final p = TradeCommandParser.parse(s);
        expect(p, isNotNull, reason: s);
        expect(p!.command, isNull, reason: s);
        expect(p.question, contains('How much gold do you want to buy'), reason: s);
        expect(p.draft!.side, 'buy', reason: s);
        expect(p.missingSize, isTrue, reason: s);
        final c = p.withDefaultSize(0.01)!;
        expect(c.lots, 0.01, reason: s);
        expect(c.side, 'buy', reason: s);
        expect(c.defaultSize, isTrue, reason: s);
      }
      for (final s in ['sell a trade', 'sell', 'sell gold', 'go short', 'sell a position']) {
        final p = TradeCommandParser.parse(s)!;
        expect(p.question, contains('How much gold do you want to sell'), reason: s);
        expect(p.draft!.side, 'sell', reason: s);
      }
    });
    test('a trade with no side asks buy or sell and how much', () {
      for (final s in [
        'open a trade', 'place a trade', 'make a trade', 'open a new gold trade',
        'take a position', 'friday place a trade', 'can you open a trade',
      ]) {
        final p = TradeCommandParser.parse(s);
        expect(p, isNotNull, reason: s);
        expect(p!.command, isNull, reason: s);
        expect(p.draft, isNull, reason: s);
        expect(p.missingSize, isFalse, reason: s);
        expect(p.withDefaultSize(0.01), isNull, reason: s);
        expect(p.question, contains('Buy or sell'), reason: s);
      }
    });
    test('default size keeps SL/TP; a wrong explicit size is not replaced', () {
      final p = TradeCommandParser.parse('sell gold sl 4150 tp 4080')!;
      final c = p.withDefaultSize(0.05)!;
      expect(c.sl, 4150);
      expect(c.tp, 4080);
      expect(c.lots, 0.05);
      final bad = TradeCommandParser.parse('buy gold 0.001 lot')!;
      expect(bad.missingSize, isFalse);
      expect(bad.withDefaultSize(0.01), isNull);
      expect(TradeCommandParser.validDefaultLots(0.01), isTrue);
      expect(TradeCommandParser.validDefaultLots(0.005), isFalse);
      expect(TradeCommandParser.validDefaultLots(0), isFalse);
      expect(TradeCommandParser.validDefaultLots(500), isFalse);
    });
    test('ambiguous or invalid sizes ask instead of guessing', () {
      expect(question('buy gold 0.001 lot'), contains('0.01 lot'));
      expect(question('buy gold 0.5 oz'), contains('0.01 lot'));
      expect(question('buy gold 0 lot'), contains('above zero'));
      expect(question('buy gold 500 lots'), contains('limit'));
      expect(question('buy gold 0.1 2310 2280'), contains('which number'));
      expect(question('buy gold 0.1 sl'), contains('SL/TP'));
    });
    test('limit / pending orders are not market orders', () {
      expect(question('buy gold 0.1 at 2300'), contains('market'));
      expect(question('buy gold limit 0.1'), contains('market'));
    });
    test('size replies', () {
      expect(TradeCommandParser.parseSizeReply('0.05')!.lots, 0.05);
      expect(TradeCommandParser.parseSizeReply('0.05 lot')!.lots, 0.05);
      expect(TradeCommandParser.parseSizeReply('5 oz')!.lots, 0.05);
      expect(TradeCommandParser.parseSizeReply('make it 0.2 lots')!.lots, 0.2);
      expect(TradeCommandParser.parseSizeReply('0.005')!.error, isNotNull);
      expect(TradeCommandParser.parseSizeReply('what is the price'), isNull);
    });
  });

  group('close orders', () {
    test('close my trade', () {
      for (final s in ['close my trade', 'Close the trade.', 'close my gold position', 'exit trade', 'close my paper trade in sona']) {
        final c = cmd(s);
        expect(c.op, TradeOp.close, reason: s);
        expect(c.all, isFalse, reason: s);
        expect(c.side, isNull, reason: s);
      }
    });
    test('close all', () {
      for (final s in ['close all trades', 'close all my positions', 'close my trades', 'close both trades']) {
        final c = cmd(s);
        expect(c.all, isTrue, reason: s);
        expect(c.side, isNull, reason: s);
      }
    });
    test('direction filter', () {
      expect(cmd('close my buy').side, 'buy');
      expect(cmd('close my buy').all, isFalse);
      expect(cmd('close the sell trade').side, 'sell');
      expect(cmd('close all sells').all, isTrue);
      expect(cmd('close all sells').side, 'sell');
      expect(cmd('close my long').side, 'buy');
    });
  });

  test('ordinary messages are not trade commands', () {
    for (final s in [
      'buy milk',
      'buy me a coffee',
      'sell my old phone',
      'buy 2 apples',
      'close all apps',
      'close whatsapp',
      'close it',
      'what is the gold price',
      'my open trades',
      'remind me to buy gold at 5',
      'long',
      'short',
      'send whatsapp to mom buy gold 0.1',
      'set volume 40',
      'place an order',
      'buy me a coffee please',
      'buy a gift',
      'sell a car',
      'open a new tab',
    ]) {
      expect(TradeCommandParser.parse(s), isNull, reason: s);
    }
  });
}
