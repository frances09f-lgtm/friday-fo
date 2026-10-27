import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:friday/models/friday_response.dart';
import 'package:friday/services/ai/ai_brain.dart';
import 'package:friday/services/ai/local_model_service.dart';
import 'package:friday/services/device/device_hub.dart';
import 'package:friday/services/device/reminder_service.dart';
import 'package:friday/services/intent_router.dart';
import 'package:friday/services/oro/oro_bridge.dart';
import 'package:friday/services/oro/trade_command.dart';
import 'package:friday/services/oro/trade_flow.dart';
import 'package:friday/services/speech/speech_service.dart';
import 'package:friday/services/storage/chat_store.dart';
import 'package:friday/services/storage/settings_store.dart';
import 'package:friday/state/friday_controller.dart';
import 'package:friday/ui/screens/home_screen.dart';

class _Brain extends AIBrain {
  _Brain(SettingsStore s) : super(settings: s, local: LocalModelService());
  int calls = 0;
  @override
  Future<FridayResponse> ask(String userText, {List<dynamic> history = const []}) async {
    calls++;
    return const FridayResponse(reply: 'brain reply', action: FridayAction(type: FridayActionType.none));
  }
}

class _Router extends IntentRouter {
  _Router() : super(deviceHub: DeviceHub(), reminders: ReminderService());
  @override
  Future<String> executeAll(List<FridayAction> actions) async => '';
}

class _Speech extends SpeechService {
  final spoken = <String>[];
  @override
  Future<void> speak(String text, {String locale = 'en-IN'}) async => spoken.add(text);
}

class _Desk implements OroTradeDesk {
  String supportWord = 'ok';
  OroSnapshot? snap;
  final submitted = <Map<String, dynamic>>[];
  String? Function(Map<String, dynamic> order)? answer;
  @override
  Future<String> support() async => supportWord;
  @override
  Future<OroSnapshot?> snapshot() async => snap;
  @override
  Future<String> submit(String orderJson) async {
    submitted.add(Map<String, dynamic>.from(jsonDecode(orderJson) as Map));
    return supportWord;
  }
  @override
  Future<String?> result(String id) async =>
      submitted.isEmpty || answer == null ? null : answer!(submitted.last);
}

final _now = DateTime.now().millisecondsSinceEpoch;

OroSnapshot _snap({List<Map<String, dynamic>> open = const [], int? quoteAt, bool known = true}) =>
    OroSnapshot.parse(jsonEncode({
      'ts': _now,
      'bid': 4120.10,
      'ask': 4120.40,
      'quoteAt': quoteAt ?? _now - 3000,
      'balance': 10000,
      'accountAt': _now - 5000,
      'accountKnown': known,
      'open': open,
    }))!;

Future<(FridayController, _Desk, _Brain, _Speech)> _setup({bool speak = false}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final settings = SettingsStore(const FlutterSecureStorage(), prefs);
  settings.speakReplies = speak;
  final desk = _Desk()..snap = _snap();
  final brain = _Brain(settings);
  final speech = _Speech();
  final c = FridayController(
    brain: brain,
    router: _Router(),
    chatStore: ChatStore(prefs),
    speech: speech,
    settings: settings,
    tradeDesk: desk,
    tradeTimeout: const Duration(milliseconds: 300),
    tradePoll: const Duration(milliseconds: 10),
  );
  return (c, desk, brain, speech);
}

String _last(FridayController c) => c.messages.last.text;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('plan', () {
    test('open confirmation shows side, size, symbol, price, age, TP/SL', () {
      final p = TradeFlow.plan(const TradeCommand.open(side: 'buy', lots: 0.1, tp: 4150, sl: 4100), _snap(), nowMs: _now);
      expect(p.ready, isTrue);
      expect(p.text, contains('BUY 0.10 lots (10 oz) XAU/USD'));
      expect(p.text, contains('ask: 4,120.40 (just now)'));
      expect(p.text, contains('TP 4,150.00 · SL 4,100.00'));
      expect(p.spoken, contains('Say confirm or cancel'));
    });
    test('stale price is called out', () {
      final p = TradeFlow.plan(const TradeCommand.open(side: 'sell', lots: 0.01), _snap(quoteAt: _now - 5 * 60000), nowMs: _now);
      expect(p.text, contains('bid: 4,120.10 (5 min old)'));
      expect(p.text, contains('not live'));
    });
    test('TP/SL on the wrong side is refused before confirming', () {
      final p = TradeFlow.plan(const TradeCommand.open(side: 'sell', lots: 0.05, sl: 2310, tp: 2280), _snap(), nowMs: _now);
      expect(p.ready, isFalse);
      expect(p.text, contains('Stop loss must be above'));
      expect(p.text, contains('No order sent'));
    });
    test('no snapshot / not synced', () {
      expect(TradeFlow.plan(const TradeCommand.close(), null, nowMs: _now).text, contains("couldn't read Sona"));
      expect(TradeFlow.plan(const TradeCommand.close(), _snap(known: false), nowMs: _now).text, contains("hasn't synced"));
    });
    test('close picks exactly one trade or asks', () {
      final two = _snap(open: [
        {'id': 'a1', 'dir': 'buy', 'qty': 10, 'entry': 4100.0},
        {'id': 'b2', 'dir': 'sell', 'qty': 5, 'entry': 4130.0},
      ]);
      final ask = TradeFlow.plan(const TradeCommand.close(), two, nowMs: _now);
      expect(ask.ready, isFalse);
      expect(ask.text, contains('You have 2 open trades'));
      final buy = TradeFlow.plan(const TradeCommand.close(side: 'buy'), two, nowMs: _now);
      expect(buy.ready, isTrue);
      expect(buy.targets.single.id, 'a1');
      expect(buy.text, contains('BUY 0.10 lot (10 oz) at 4,100.00, up \$201.00'));
      final all = TradeFlow.plan(const TradeCommand.close(all: true), two, nowMs: _now);
      expect(all.targets.length, 2);
      expect(TradeFlow.plan(const TradeCommand.close(), _snap(), nowMs: _now).text, contains('No open trades'));
    });
    test('old Sona without position ids cannot close', () {
      final p = TradeFlow.plan(const TradeCommand.close(), _snap(open: [{'dir': 'buy', 'qty': 10, 'entry': 4100.0}]), nowMs: _now);
      expect(p.text, contains('too old'));
    });
  });

  test('reply words', () {
    for (final s in ['yes', 'Yes.', 'confirm', 'Confirm', 'go ahead', 'do it', 'okay']) {
      expect(TradeFlow.classifyReply(s), TradeReply.confirm, reason: s);
    }
    for (final s in ['no', 'Cancel', 'stop', 'never mind']) {
      expect(TradeFlow.classifyReply(s), TradeReply.cancel, reason: s);
    }
    expect(TradeFlow.classifyReply('what is the gold price'), TradeReply.other);
  });

  group('confirm flow', () {
    test('nothing is sent before confirm; confirm sends and shows the fill', () async {
      final (c, desk, brain, _) = await _setup();
      desk.answer = (o) => jsonEncode({
            'id': o['id'], 'status': 'done',
            'fill': {'side': 'buy', 'qty': 10, 'entry': 4120.55, 'tp': 4150, 'sl': 4100},
          });
      await c.send('buy gold 0.1 lot tp 4150 sl 4100');
      expect(desk.submitted, isEmpty);
      expect(c.pendingTrade, isNotNull);
      expect(c.messages.last.id, c.pendingTrade!.messageId);
      expect(_last(c), startsWith('Confirm paper trade: BUY 0.10 lots (10 oz)'));
      await c.send('confirm');
      expect(desk.submitted.single['op'], 'open');
      expect(desk.submitted.single['side'], 'buy');
      expect(desk.submitted.single['qty'], 10);
      expect(desk.submitted.single['tp'], 4150);
      expect(desk.submitted.single['sl'], 4100);
      expect(_last(c), 'Done. Sona opened BUY 0.10 lots (10 oz) XAU/USD at 4,120.55. TP 4,150.00 · SL 4,100.00. Paper trade.');
      expect(c.pendingTrade, isNull);
      expect(brain.calls, 0);
      // A second "yes" does not resend.
      await c.send('yes');
      expect(desk.submitted.length, 1);
    });

    test('cancel sends nothing', () async {
      final (c, desk, _, _) = await _setup();
      await c.send('sell 0.05 lot');
      await c.send('cancel');
      expect(desk.submitted, isEmpty);
      expect(_last(c), contains('No order was sent'));
      expect(c.pendingTrade, isNull);
    });

    test('an unrelated message drops the confirmation', () async {
      final (c, desk, brain, _) = await _setup();
      await c.send('sell 0.05 lot');
      await c.send('what time is it');
      expect(desk.submitted, isEmpty);
      expect(c.pendingTrade, isNull);
      expect(c.messages.any((m) => m.text.startsWith('Dropped the pending trade')), isTrue);
      expect(brain.calls, 1);
    });

    test('missing size: asks, then a size reply builds the order', () async {
      final (c, desk, _, _) = await _setup();
      await c.send('buy gold');
      expect(_last(c), contains('How much gold'));
      expect(c.pendingTrade, isNull);
      await c.send('0.02');
      expect(c.pendingTrade, isNotNull);
      expect(_last(c), contains('BUY 0.02 lots (2 oz)'));
      expect(desk.submitted, isEmpty);
    });

    test('vague "buy a trade" asks for the size, then builds the order',
        () async {
      final (c, desk, brain, _) = await _setup();
      await c.send('buy a trade');
      expect(_last(c), contains('How much gold do you want to buy'));
      expect(brain.calls, 0);
      await c.send('0.1 lot');
      expect(c.pendingTrade, isNotNull);
      expect(_last(c), contains('BUY 0.10 lots'));
      expect(desk.submitted, isEmpty);
    });

    test('"open a trade" asks buy or sell and how much', () async {
      final (c, desk, brain, _) = await _setup();
      await c.send('open a trade');
      expect(_last(c), contains('Buy or sell'));
      expect(brain.calls, 0);
      await c.send('sell 0.05 lot');
      expect(c.pendingTrade, isNotNull);
      expect(desk.submitted, isEmpty);
    });

    test('Sona rejection is said plainly', () async {
      final (c, desk, _, _) = await _setup();
      desk.answer = (o) => jsonEncode({'id': o['id'], 'status': 'rejected', 'message': 'Market closed for the weekend - reopens Mon 3:30 AM'});
      await c.send('buy gold 0.01 lot');
      await c.send('yes');
      expect(_last(c), 'Sona did not place the trade: Market closed for the weekend - reopens Mon 3:30 AM');
    });

    test('no answer from Sona: unknown outcome, never resent', () async {
      final (c, desk, _, _) = await _setup();
      await c.send('buy gold 0.01 lot');
      await c.send('confirm');
      expect(desk.submitted.length, 1);
      expect(_last(c), contains('did not report back'));
      expect(_last(c), contains('will not send it again'));
    });

    test('Sona missing / too old', () async {
      final (c, desk, _, _) = await _setup();
      desk.supportWord = 'missing';
      await c.send('buy gold 0.01 lot');
      expect(_last(c), contains("Sona isn't installed"));
      expect(c.pendingTrade, isNull);
      desk.supportWord = 'unsupported';
      await c.send('close my trade');
      expect(_last(c), contains('too old'));
    });

    test('close confirms the exact trade and reports P/L', () async {
      final (c, desk, _, _) = await _setup();
      desk.snap = _snap(open: [{'id': 'p9', 'dir': 'sell', 'qty': 5, 'entry': 4130.0, 'tp': 4100.0}]);
      desk.answer = (o) => jsonEncode({
            'id': o['id'], 'status': 'done',
            'closed': [{'side': 'sell', 'qty': 5, 'exit': 4120.45, 'pnl': 47.75}],
          });
      await c.send('close my trade');
      expect(_last(c), contains('SELL 0.05 lot (5 oz) at 4,130.00 (TP 4,100.00)'));
      await c.send('yes');
      expect(desk.submitted.single['op'], 'close');
      expect(desk.submitted.single['ids'], ['p9']);
      expect(_last(c), 'Closed SELL 0.05 lot (5 oz) at 4,120.45, P/L +\$47.75.');
    });

    test('expired confirmation is not executed', () async {
      final (c, _, _, _) = await _setup();
      await c.send('buy gold 0.01 lot');
      final p = c.pendingTrade!;
      // Simulate the 2-minute window passing.
      expect(p.expired(p.at.add(const Duration(minutes: 3))), isTrue);
    });

    test('voice confirmation is spoken', () async {
      final (c, _, _, speech) = await _setup(speak: true);
      await c.send('sell gold 0.05 lot');
      expect(speech.spoken.last, contains('Sell 0.05 lots of gold'));
      expect(speech.spoken.last, contains('Say confirm or cancel'));
    });
  });

  testWidgets('Confirm / Cancel buttons call back', (t) async {
    var confirmed = 0, cancelled = 0;
    await t.pumpWidget(MaterialApp(home: Scaffold(body: TradeConfirmButtons(
      onConfirm: () => confirmed++, onCancel: () => cancelled++))));
    await t.tap(find.byKey(const ValueKey('trade-confirm')));
    await t.tap(find.byKey(const ValueKey('trade-cancel')));
    expect(confirmed, 1);
    expect(cancelled, 1);
  });
}
