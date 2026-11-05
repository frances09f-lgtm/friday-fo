import 'dart:async';
import 'dart:convert';

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
import 'package:friday/services/oro/trade_flow.dart';
import 'package:friday/services/speech/speech_service.dart';
import 'package:friday/services/storage/chat_store.dart';
import 'package:friday/services/storage/settings_store.dart';
import 'package:friday/state/friday_controller.dart';

class _Brain extends AIBrain {
  _Brain(SettingsStore s) : super(settings: s, local: LocalModelService());
  Completer<FridayResponse>? stall;
  @override
  Future<FridayResponse> ask(String userText,
      {List<dynamic> history = const []}) {
    if (stall != null && !stall!.isCompleted) return stall!.future;
    return Future.value(const FridayResponse(
        reply: 'brain reply',
        action: FridayAction(type: FridayActionType.none)));
  }
}

class _Router extends IntentRouter {
  _Router() : super(deviceHub: DeviceHub(), reminders: ReminderService());
  Completer<String>? held;
  int calls = 0;
  @override
  Future<String> executeAll(List<FridayAction> actions) async {
    calls++;
    return held?.future ?? Future.value('');
  }
}

class _Speech extends SpeechService {
  final spoken = <String>[];
  @override
  Future<void> speak(String text, {String locale = 'en-IN'}) async =>
      spoken.add(text);
}

class _Desk implements OroTradeDesk {
  OroSnapshot? snap;
  final submitted = <Map<String, dynamic>>[];
  Completer<String?>? pendingResult;
  Completer<String>? supportWait;
  Completer<OroSnapshot?>? snapshotWait;
  @override
  Future<String> support() async => supportWait?.future ?? Future.value('ok');
  @override
  Future<OroSnapshot?> snapshot() async =>
      snapshotWait?.future ?? Future.value(snap);
  @override
  Future<String> submit(String orderJson) async {
    submitted.add(Map<String, dynamic>.from(jsonDecode(orderJson) as Map));
    return 'ok';
  }

  @override
  Future<String?> result(String id) async {
    final p = pendingResult;
    if (p == null || !p.isCompleted) return null;
    return p.future;
  }
}

OroSnapshot _snap() {
  final now = DateTime.now().millisecondsSinceEpoch;
  return OroSnapshot.parse(jsonEncode({
    'ts': now,
    'bid': 4120.10,
    'ask': 4120.40,
    'quoteAt': now - 3000,
    'balance': 10000,
    'accountAt': now - 5000,
    'accountKnown': true,
    'open': const [],
  }))!;
}

Future<(FridayController, _Brain, _Desk)> _setup(
    {Duration? requestTimeout, Duration? tradeTimeout}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final settings = SettingsStore(const FlutterSecureStorage(), prefs);
  final brain = _Brain(settings);
  final desk = _Desk()..snap = _snap();
  final c = FridayController(
    brain: brain,
    router: _Router(),
    chatStore: ChatStore(prefs),
    speech: _Speech(),
    settings: settings,
    tradeDesk: desk,
    tradeTimeout: tradeTimeout ?? const Duration(seconds: 5),
    tradePoll: const Duration(milliseconds: 10),
    requestTimeout: requestTimeout ?? const Duration(seconds: 60),
  );
  return (c, brain, desk);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a hung model request can be cancelled; its late reply is dropped',
      () async {
    final (c, brain, _) = await _setup();
    brain.stall = Completer<FridayResponse>();
    // "bio trade of 0.02 lot" is not trade vocabulary: it goes to the model.
    unawaited(c.send('bio trade of 0.02 lot'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(c.busy, isTrue);

    c.cancel();
    expect(c.busy, isFalse);
    expect(c.phase, 'Ready');
    expect(c.messages.last.text, 'Cancelled. Nothing was done.');

    // The hung model finally answers: the stale reply must not appear.
    brain.stall!.complete(const FridayResponse(
        reply: 'late model answer',
        action: FridayAction(type: FridayActionType.none)));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(
        c.messages.any((m) => m.text.contains('late model answer')), isFalse);
    expect(c.busy, isFalse);

    // The next request runs normally after a cancel.
    brain.stall = null;
    await c.send('hello there');
    expect(c.messages.last.text, 'brain reply');
    expect(c.busy, isFalse);
  });

  test('a model request that never answers times out instead of spinning',
      () async {
    final (c, brain, _) =
        await _setup(requestTimeout: const Duration(milliseconds: 200));
    brain.stall = Completer<FridayResponse>();
    await c.send('some question for the model');
    expect(c.busy, isFalse);
    expect(c.messages.last.text, contains('timed out'));
    expect(c.phase, 'Ready');
  });

  test(
      'cancel while Sona holds the order is honest, and the real result still arrives',
      () async {
    final (c, _, desk) = await _setup();
    desk.pendingResult = Completer<String?>();
    await c.send('buy gold 0.01 lot');
    expect(c.messages.last.text, contains('Confirm paper trade: BUY'));

    unawaited(c.send('Confirm'));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(desk.submitted, hasLength(1));
    expect(c.busy, isTrue);
    expect(c.phase, 'Sending to Sona');

    c.cancel();
    expect(c.busy, isFalse);
    expect(c.messages.last.text, contains('may already be with Sona'));
    expect(c.messages.last.text, isNot(contains('No order was sent')));

    // Sona's real fill is still reported when it arrives.
    desk.pendingResult!.complete(jsonEncode({
      'id': desk.submitted.last['id'],
      'status': 'done',
      'fill': {'id': 'p1', 'side': 'buy', 'qty': 1, 'entry': 4120.40},
    }));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(c.messages.any((m) => m.text.startsWith('Done. Sona opened BUY')),
        isTrue);
  });

  test('cancel during Sona support cannot arm a confirmation', () async {
    final (c, _, desk) = await _setup();
    desk.supportWait = Completer<String>();
    final work = c.send('buy gold 0.01 lot');
    await Future<void>.delayed(const Duration(milliseconds: 25));
    c.cancel();
    await work;
    desk.supportWait!.complete('ok');
    await Future<void>.delayed(const Duration(milliseconds: 25));
    expect(c.pendingTrade, isNull);
    expect(desk.submitted, isEmpty);
    expect(c.messages.any((m) => m.text.contains('Confirm paper trade:')),
        isFalse);
  });

  test('cancel during snapshot cannot restore confirmation or reset new run',
      () async {
    final (c, brain, desk) = await _setup();
    desk.snapshotWait = Completer<OroSnapshot?>();
    final work = c.send('buy gold 0.01 lot');
    await Future<void>.delayed(const Duration(milliseconds: 25));
    c.cancel();
    await work;
    brain.stall = Completer<FridayResponse>();
    final next = c.send('tell me something');
    await Future<void>.delayed(const Duration(milliseconds: 25));
    desk.snapshotWait!.complete(_snap());
    await Future<void>.delayed(const Duration(milliseconds: 25));
    expect(c.pendingTrade, isNull);
    expect(c.busy, isTrue);
    brain.stall!.complete(const FridayResponse(
        reply: 'new request',
        action: FridayAction(type: FridayActionType.none)));
    await next;
    expect(c.messages.last.text, 'new request');
  });

  test('cancelled model action cannot execute', () async {
    final (c, brain, _) = await _setup();
    brain.stall = Completer<FridayResponse>();
    final work = c.send('tell me a story');
    await Future<void>.delayed(const Duration(milliseconds: 25));
    c.cancel();
    await work;
    brain.stall!.complete(const FridayResponse(
        reply: 'late action',
        action: FridayAction(type: FridayActionType.openApp, app: 'camera')));
    await Future<void>.delayed(const Duration(milliseconds: 25));
    expect(c.messages.any((m) => m.text.contains('late action')), isFalse);
  });

  test('cancel stops a later action in a sequence', () async {
    final (c, brain, _) = await _setup();
    final router = c.router as _Router;
    router.held = Completer<String>();
    brain.stall = Completer<FridayResponse>();
    final work = c.send('some model question');
    await Future<void>.delayed(const Duration(milliseconds: 25));
    brain.stall!.complete(const FridayResponse(
        reply: 'actions',
        action: FridayAction(type: FridayActionType.torchOff),
        extraActions: [
          FridayAction(type: FridayActionType.openApp, app: 'camera')
        ]));
    await Future<void>.delayed(const Duration(milliseconds: 25));
    expect(router.calls, 1);
    c.cancel();
    await work;
    router.held!.complete('first action finished');
    await Future<void>.delayed(const Duration(milliseconds: 25));
    expect(router.calls, 1);
    expect(c.messages.last.text, contains('already started'));
  });

  test('cancel on an idle controller does nothing', () async {
    final (c, _, _) = await _setup();
    final before = c.messages.length;
    c.cancel();
    expect(c.messages.length, before);
    expect(c.busy, isFalse);
  });
}
