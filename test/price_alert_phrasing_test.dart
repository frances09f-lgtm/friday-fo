import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:friday/models/friday_response.dart';
import 'package:friday/services/ai/ai_brain.dart';
import 'package:friday/services/ai/local_model_service.dart';
import 'package:friday/services/ai/offline_engine.dart';
import 'package:friday/services/device/device_hub.dart';
import 'package:friday/services/device/reminder_service.dart';
import 'package:friday/services/intent_router.dart';
import 'package:friday/services/reminder_parser.dart';
import 'package:friday/services/speech/speech_service.dart';
import 'package:friday/services/speech/voice_pick.dart';
import 'package:friday/services/speech/voice_repair.dart';
import 'package:friday/services/storage/chat_store.dart';
import 'package:friday/services/storage/settings_store.dart';
import 'package:friday/services/tasks/gold_task.dart';
import 'package:friday/services/tasks/task_service.dart';
import 'package:friday/state/friday_controller.dart';

/// Expect [text] to be read, without asking, as a gold alert.
void expectAlert(String text, String direction, double threshold,
    {int minutes = 5}) {
  final r = GoldTaskRequest.parse(text);
  expect(r, isNotNull, reason: text);
  expect(r!.direction, direction, reason: text);
  expect(r.threshold, threshold, reason: text);
  expect(r.intervalMinutes, minutes, reason: text);
}

class _FakeRouter extends IntentRouter {
  _FakeRouter() : super(deviceHub: DeviceHub(), reminders: ReminderService());
  @override
  Future<String> executeAll(List<FridayAction> actions) async => '';
}

class _FakeSpeech extends SpeechService {
  @override
  Future<void> speak(String text, {String locale = 'en-IN'}) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group("Abhi's exact sentences", () {
    test('"about" before the number is "above"', () {
      expectAlert('tell me when gold goes about for 4000', 'above', 4000);
      expectAlert('tell me when gold goes about 4000', 'above', 4000);
      // As a recognizer writes it: capital, comma, full stop.
      expectAlert('Tell me when gold goes about 4,000.', 'above', 4000);
    });
    test('the offline engine no longer refuses them', () {
      for (final s in [
        'tell me when gold goes about for 4000',
        'tell me when gold goes about 4000',
      ]) {
        final r = const OfflineEngine().handle(s);
        expect(r.reply, isNot(contains('No alert was created')), reason: s);
      }
    });
  });

  group('direction words', () {
    test('above', () {
      for (final s in [
        'alert me when gold goes above 4000',
        'alert me when gold goes abv 4000',
        'alert me when gold goes over 4000',
        'notify me when gold is more than 4000',
        'notify me when gold is greater than 4000',
        'tell me when gold rises to 4000',
        'tell me when gold goes up to 4000',
        'tell me when gold climbs past 4000',
        'tell me when gold exceeds 4000',
        'tell me when gold breaks above 4000',
        'tell me when gold crosses above 4000',
        'ping me when gold > 4000',
        'ping me when gold >= 4000',
        'ping me when gold ≥ 4000',
        'alert me when gold price rises above 4000',
      ]) {
        expectAlert(s, 'above', 4000);
      }
    });
    test('below', () {
      for (final s in [
        'alert me when gold goes below 3950',
        'alert me when gold goes under 3950',
        'alert me when gold drops to 3950',
        'alert me when gold falls to 3950',
        'tell me when gold dips to 3950',
        'tell me when gold is less than 3950',
        'tell me when gold goes down to 3950',
        'tell me when gold breaks below 3950',
        'ping me when gold < 3950',
        'ping me when gold <= 3950',
        'ping me when gold ≤ 3950',
        'alert me when gold price goes below 3950',
      ]) {
        expectAlert(s, 'below', 3950);
      }
    });
    test('the direction word nearest the number wins', () {
      expectAlert('tell me if gold falls and goes back above 4000', 'above', 4000);
    });
  });

  group('filler and number formats', () {
    test('for, around, rupee, dollar, commas, 4k, words', () {
      expectAlert('alert me when gold goes above for 4000', 'above', 4000);
      expectAlert('alert me when gold goes above ₹4,000', 'above', 4000);
      expectAlert(r'alert me when gold goes above $4,000', 'above', 4000);
      expectAlert('alert me when gold goes above rs 4000', 'above', 4000);
      expectAlert('alert me when gold goes above usd 4000', 'above', 4000);
      expectAlert('alert me when gold goes above 4k', 'above', 4000);
      expectAlert('alert me when gold goes above 4.1k', 'above', 4100);
      expectAlert('alert me when gold goes above 4 000', 'above', 4000);
      expectAlert('alert me when gold goes above four thousand', 'above', 4000);
      expectAlert('alert me when gold goes above 4012.5', 'above', 4012.5);
      expectAlert('tell me when gold is around 4000', 'auto', 4000);
    });
    test('intervals', () {
      expectAlert('check gold every 10 minutes and tell me if it goes above 4000',
          'above', 4000, minutes: 10);
      expectAlert('alert me when gold goes above 4000 every hour', 'above', 4000,
          minutes: 60);
      expectAlert('check gold every 2 hours and alert me if it is below 4150.5',
          'below', 4150.5, minutes: 120);
      expectAlert('check gold every five minutes and alert me above 4000',
          'above', 4000);
    });
  });

  group('no direction: picked from the saved quote', () {
    test('neutral phrasings read as auto', () {
      for (final s in [
        'tell me when gold hits 4000',
        'when gold is 4000',
        'alert me when gold reaches 4000',
        'notify me when gold touches 4000',
        'tell me when gold crosses 4000',
        'tell me when gold goes to 4000',
        'set an alert for gold at 4000',
        'gold alert 4000',
      ]) {
        expectAlert(s, 'auto', 4000);
      }
    });
    test('target above the quote waits for a rise, below for a fall', () {
      final r = GoldTaskRequest.parse('tell me when gold hits 4000')!;
      expect(r.resolve(3962.4).direction, 'above');
      expect(r.resolve(4031).direction, 'below');
      // No quote yet: either way.
      expect(r.resolve(null).direction, 'cross');
      // An explicit direction is never changed.
      expect(GoldTaskRequest.parse('alert me when gold goes below 4000')!
              .resolve(3900)
              .direction,
          'below');
    });
    test('the reply confirms what was set', () {
      final r = GoldTaskRequest.parse('tell me when gold hits 4000')!;
      expect(r.resolve(3962.4).confirmation(currentPrice: 3962.4),
          'Alert set: gold above 4,000 (now 3,962). Checking every 5 min.');
      expect(r.resolve(null).confirmation(),
          startsWith('Alert set: gold reaches 4,000. Checking every 5 min.'));
      expect(r.resolve(null).confirmation(), contains('either side'));
      final ok = r
          .resolve(3962.4)
          .createdReply('Saved a one-shot gold above 4000.0 alert, checking about every 5 minutes.',
              currentPrice: 3962.4);
      expect(ok, 'Alert set: gold above 4,000 (now 3,962). Checking every 5 min.');
      // The phone's own words when it did not save.
      expect(r.createdReply('Gold alert notifications are disabled.'),
          'Gold alert notifications are disabled.');
      // Already past the target.
      expect(
          GoldTaskRequest.parse('alert me when gold goes above 4000')!
              .createdReply('Saved a one-shot gold above 4000.0 alert',
                  currentPrice: 4010),
          contains('already above'));
    });
    test('only a recent saved quote is used', () {
      const now = 1000000000;
      expect(GoldTaskRequest.usableQuote(3960, 3962, now - 60000, now), 3961);
      expect(GoldTaskRequest.usableQuote(3960, null, now - 60000, now), 3960);
      expect(GoldTaskRequest.usableQuote(3960, 3962, 0, now), isNull);
      expect(
          GoldTaskRequest.usableQuote(3960, 3962, now - 13 * 3600000, now), isNull);
      expect(GoldTaskRequest.usableQuote(3962, 3960, now - 60000, now), 3962);
    });
    test('a cross task reads plainly on the Tasks page', () {
      expect(taskTitle({'direction': 'cross', 'threshold': 4000}),
          'Gold reaches 4000 (either way)');
      expect(taskTitle({'direction': 'above', 'threshold': 4000.0}),
          'Gold above 4000');
    });
  });

  group('never a refusal when the asset and a number are there', () {
    test('every gold-and-number alert is read (or offered as a guess)', () {
      for (final s in [
        'tell me when gold goes about for 4000',
        'tell me when gold goes about 4000',
        'tell me when gold hits 4000',
        'when gold is 4000',
        'alert me when gold goes ebav 4000',
        'tell me when gold gos abuf 4000',
        'check gold every 1 minute and tell me if it goes below 4150',
        'alert me when xauusd goes above 4050',
      ]) {
        expect(GoldTaskRequest.read(s), isNotNull, reason: s);
        final reply = const OfflineEngine().handle(s).reply;
        expect(reply, isNot(contains('No alert was created')), reason: s);
      }
    });
    test('only a missing asset is asked about', () {
      expect(GoldTaskRequest.isAssetlessAlert('tell me when the price goes above 4000'),
          isTrue);
      expect(GoldTaskRequest.isAssetlessAlert('tell me when it goes above 4000'),
          isTrue);
      expect(GoldTaskRequest.isAssetlessAlert('tell me when gold goes above 4000'),
          isFalse);
      expect(GoldTaskRequest.isAssetlessAlert('tell me when battery is above 80'),
          isFalse);
    });
    test('gold with no number asks for the price, not for a direction', () {
      final r = const OfflineEngine().handle('alert me when gold goes up');
      expect(r.reply, contains('What price'));
      expect(r.reply, isNot(contains('No alert was created')));
    });
  });

  group('not alerts', () {
    test('questions, trades and other assets stay out', () {
      for (final s in [
        'is gold above 4000',
        'when was gold above 4000',
        'buy gold at 4000',
        'sell 0.1 lots of gold when it hits 4000',
        'what is the gold price',
        'notify me if my trade reaches TP',
        'check silver every hour and tell me if it goes below 40',
        'tell me when it goes above 4000',
        'remind me to call mom at 5 pm',
      ]) {
        expect(GoldTaskRequest.parse(s), isNull, reason: s);
      }
    });
  });

  group('voice mishearings (30+ phrasings)', () {
    // [heard, direction, threshold, acted on at once?]
    final table = <(String, String, double, bool)>[
      ('tell me when gold goes about for 4000', 'above', 4000, true),
      ('tell me when gold goes about 4000', 'above', 4000, true),
      ('tell me when gold goes a bove 4000', 'above', 4000, true),
      ('tell me when gold goes a bow 4000', 'above', 4000, true),
      ('tell me when gold goes a bob 4000', 'above', 4000, true),
      ('tell me when gold goes abuv 4000', 'above', 4000, true),
      ('tell me when gold goes abov 4000', 'above', 4000, true),
      ('tell me when gold goes abow 4000', 'above', 4000, true),
      ('tell me when gold goes ever 4000', 'above', 4000, true),
      ('tell me when gold goes every 4000', 'above', 4000, true),
      ('tell me when gold goes ab of 4000', 'above', 4000, true),
      ('alert me when gold trades about 4000', 'above', 4000, true),
      ('tell me when gold goes blow 3950', 'below', 3950, true),
      ('tell me when gold goes blew 3950', 'below', 3950, true),
      ('tell me when gold goes bilo 3950', 'below', 3950, true),
      ('tell me when gold goes bellow 3950', 'below', 3950, true),
      ('tell me when gold goes be low 3950', 'below', 3950, true),
      ('tell me when gold goes pillow 3950', 'below', 3950, true),
      ('tell me when goal goes above 4000', 'above', 4000, true),
      ('tell me when gol goes above 4000', 'above', 4000, true),
      ('tell me when gould goes below 3950', 'below', 3950, true),
      ("tell me when gold's price goes above 4000", 'above', 4000, true),
      ('a lot me when gold goes above 4000', 'above', 4000, true),
      ('tell me when gold goes above for thousand', 'above', 4000, true),
      ('tell me when gold goes above four thousand one hundred', 'above', 4100, true),
      ('tell me when gold goes below forty one hundred', 'below', 4100, true),
      ('tell me when gold goes above 4 thousand', 'above', 4000, true),
      ('tell me when gold goes bilo for thousand', 'below', 4000, true),
      ('notify me when gold goes above three thousand nine hundred fifty', 'above', 3950, true),
      // Sound-alike guesses: asked as "Did you mean ...?", never refused.
      ('tell me when cold goes above 4000', 'above', 4000, false),
      // An unknown word before the number: no guess needed, the saved
      // quote picks the side (the reply names it: "gold above 4,000").
      ('tell me when gold goes abeve 4000', 'auto', 4000, true),
      ('tell me when gold goes bilow 3950', 'below', 3950, true),
      ('tell me when gold goes belwo 3950', 'auto', 3950, true),
      ('tell me when gold goes ebav 4000', 'auto', 4000, true),
      ('tell me when cold goes abuv 4000', 'above', 4000, false),
      ('check old every 5 minutes and tell me feed goes above 4185', 'above', 4185, false),
    ];
    for (final (heard, direction, threshold, certain) in table) {
      test(heard, () {
        final r = GoldTaskRequest.read(heard);
        expect(r, isNotNull, reason: heard);
        expect(r!.request.direction, direction, reason: heard);
        expect(r.request.threshold, threshold, reason: heard);
        expect(r.certain, certain, reason: heard);
        // The "Did you mean" command reads back exactly.
        final again = GoldTaskRequest.parse(r.request.canonical);
        expect(again?.direction, direction, reason: r.request.canonical);
        expect(again?.threshold, threshold, reason: r.request.canonical);
      });
    }
    test('there are at least 30 of them', () => expect(table.length, greaterThanOrEqualTo(30)));
    test('an unrunnable interval becomes a question with a runnable one', () {
      final r =
          GoldTaskRequest.read('check gold every 1 minute and tell me if it goes below 4150')!;
      expect(r.certain, isFalse);
      expect(r.request.intervalMinutes, 5);
      expect(r.request.readable, 'alert when gold goes below 4,150');
    });
  });

  group('voice repair helpers', () {
    test('number words', () {
      expect(VoiceRepair.numbers('above four thousand'), 'above 4000');
      expect(VoiceRepair.numbers('above forty one hundred'), 'above 4100');
      expect(VoiceRepair.numbers('four thousand and fifty'), '4050');
      expect(VoiceRepair.numbers('every five minutes'), 'every 5 minutes');
      expect(VoiceRepair.numbers('every half an hour'), 'every 30 minutes');
      expect(VoiceRepair.numbers('1,00,000'), '100000');
      expect(VoiceRepair.numbers('gold 4120 now'), 'gold 4120 now');
    });
    test('soundex and distance', () {
      expect(VoiceRepair.soundex('above'), VoiceRepair.soundex('abuv'));
      expect(VoiceRepair.soundex('below'), VoiceRepair.soundex('bilo'));
      expect(VoiceRepair.distance('about', 'above'), 2);
    });
    test('known fixes only fire right before the number', () {
      // "about" as "approximately" with no number after it is left alone.
      expect(VoiceRepair.known('tell me about gold').$1, 'tell me about gold');
      expect(VoiceRepair.known('tell me when gold goes about 4000').$2,
          ['about -> above']);
    });
  });

  group('picking among recognizer alternatives', () {
    test('a close alternative that reads as a command beats an unreadable top guess', () {
      expect(
          VoicePick.choose(const [
            HeardText('tell me when cold goes abeve 4000', 0.62),
            HeardText('tell me when gold goes above 4000', 0.31),
            HeardText('tell me when gold goes of 4000', 0.2),
          ]),
          'tell me when gold goes above 4000');
    });
    test('a readable top guess is kept', () {
      expect(
          VoicePick.choose(const [
            HeardText('tell me when gold goes about 4000', 0.9),
            HeardText('tell me when gold goes below 4000', 0.4),
          ]),
          'tell me when gold goes about 4000');
    });
    test('plain conversation keeps the top guess', () {
      expect(
          VoicePick.choose(const [
            HeardText('how was your day', 0.8),
            HeardText('open whatsapp', 0.1),
          ]),
          'how was your day');
      expect(VoicePick.choose(const []), '');
    });
    test('reminders count as understood', () {
      expect(VoicePick.understood('remind me to stretch in 30 minutes'), isTrue);
      expect(ReminderParser.parseForChat('remind me when gold hits 4000', DateTime(2026)),
          isNull);
    });
  });

  group('Did you mean, in the chat', () {
    Future<FridayController> controller() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settings = SettingsStore(const FlutterSecureStorage(), prefs);
      settings.speakReplies = false;
      return FridayController(
        brain: AIBrain(settings: settings, local: LocalModelService()),
        router: _FakeRouter(),
        chatStore: ChatStore(prefs),
        speech: _FakeSpeech(),
        settings: settings,
      );
    }

    test('a sound-alike asks, Yes creates the alert', () async {
      final c = await controller();
      await c.send('tell me when cold goes above 4000');
      expect(c.messages.last.text,
          'Did you mean: alert when gold goes above 4,000? Tap Yes to set it, or Edit to fix it.');
      expect(c.pendingAlert?.messageId, c.messages.last.id);
      expect(c.pendingAlert?.request.canonical, 'alert me when gold goes above 4000');
      await c.send('Yes');
      expect(c.pendingAlert, isNull);
      // Off Android the task service says where alerts run - the create
      // path ran, not a refusal or a chat answer.
      expect(c.messages.last.text, contains('Android phone'));
    });
    test('No drops it', () async {
      final c = await controller();
      await c.send('tell me when cold goes above 4000');
      await c.send('no');
      expect(c.pendingAlert, isNull);
      expect(c.messages.last.text, startsWith('Okay, no alert was set.'));
    });
    test("Abhi's sentences go straight to creating the alert", () async {
      final c = await controller();
      await c.send('tell me when gold goes about for 4000');
      expect(c.pendingAlert, isNull);
      expect(c.messages.last.text, isNot(contains('No alert was created')));
      expect(c.messages.last.text, contains('Android phone'));
    });
    test('a missing asset is the one thing asked', () async {
      final c = await controller();
      await c.send('tell me when the price goes above 4000');
      expect(c.messages.last.text, startsWith('Which one should I watch?'));
    });
    test('PendingAlert yes / no words', () {
      for (final s in ['yes', 'Yes.', 'haan', 'ok', 'do it']) {
        expect(PendingAlert.isYes(s), isTrue, reason: s);
      }
      for (final s in ['no', 'nahi', 'cancel']) {
        expect(PendingAlert.isNo(s), isTrue, reason: s);
      }
      expect(PendingAlert.isYes('yes open whatsapp'), isFalse);
    });
  });
}
