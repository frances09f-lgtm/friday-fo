import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:friday/services/device/device_hub.dart';
import 'package:friday/state/friday_controller.dart';
import 'package:friday/models/chat_message.dart';
import 'package:friday/models/friday_response.dart';
import 'package:friday/services/ai/ai_brain.dart';
import 'package:friday/services/ai/offline_engine.dart';
import 'package:friday/services/intent_router.dart';
import 'package:friday/services/speech/speech_service.dart';
import 'package:friday/services/storage/chat_store.dart';
import 'package:friday/services/storage/settings_store.dart';

class NoBrain implements AIBrain {
  @override
  Future<FridayResponse> ask(String text,
          {List<ChatMessage> history = const []}) =>
      Future.value(const OfflineEngine().handle(text));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class RecordingRouter implements IntentRouter {
  final received = <FridayAction>[];
  String outcome = 'Recipient confirmation cancelled. No message sent.';
  @override
  Future<String> executeAll(List<FridayAction> actions) async {
    received.addAll(actions);
    return outcome;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MemoryStore implements ChatStore {
  @override
  Future<void> save(List<ChatMessage> messages) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Muted implements SettingsStore {
  @override
  bool get speakReplies => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class NoSpeech implements SpeechService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class DelayedSpeech extends NoSpeech {
  final done = Completer<void>();
  bool started = false;
  @override
  Future<void> speak(String text, {String locale = 'en-IN'}) async {
    started = true;
    await done.future;
  }
}

class SpokenSettings extends Muted {
  @override
  bool get speakReplies => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'method channel preserves recipient and verbatim body to native boundary',
      () async {
    final calls = <MethodCall>[];
    const channel = MethodChannel('friday/device');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return 'cancelled';
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    const body = '  HeLo\nPlease read this on my phone!  ';
    expect(await DeviceHub().sendWhatsApp('gourav dhavale', body), 'cancelled');
    expect(calls.single.method, 'sendWhatsApp');
    expect(calls.single.arguments, {'who': 'gourav dhavale', 'text': body});
  });
  for (final body in [
    "  HeLo\nDon't change this!  ",
    'please read this on my phone',
    'gold above 4000 every 5 minutes?',
    'hello and open camera',
  ]) {
    test(
        'controller preserves WhatsApp payload: ${body.replaceAll('\n', '\\n')}',
        () async {
      final router = RecordingRouter();
      final controller = FridayController(
          brain: NoBrain(),
          router: router,
          chatStore: MemoryStore(),
          speech: NoSpeech(),
          settings: Muted());
      await controller.send('WhatsApp to gourav dhavale saying $body');
      expect(router.received, hasLength(1));
      expect(router.received.single.type, FridayActionType.sendWhatsApp);
      expect(router.received.single.target, 'gourav dhavale');
      expect(router.received.single.body, body);
      expect(controller.messages.first.text,
          'WhatsApp to gourav dhavale saying $body');
      expect(controller.messages.last.text, contains('cancelled'));
      expect(controller.busy, isFalse);
      controller.dispose();
    });
  }
  test('real controller signals command before trailing TTS settles', () async {
    final router = RecordingRouter()..outcome = '';
    final speech = DelayedSpeech();
    final c = FridayController(
        brain: NoBrain(),
        router: router,
        chatStore: MemoryStore(),
        speech: speech,
        settings: SpokenSettings());
    var finished = false;
    final send = c.send('call Aditya Suthar').then((_) {
      finished = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(c.busy, false);
    expect(c.completedCommandRevision, 1);
    expect(speech.started, true);
    expect(finished, false);
    speech.done.complete();
    await send;
    c.dispose();
  });
  test(
      'native calls retain exact configured alias for manual and voice transcripts',
      () async {
    final calls = <MethodCall>[];
    const channel = MethodChannel('friday/device');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (c) async {
      calls.add(c);
      return 'calling';
    });
    for (final alias in ['Mimi', 'Appa', 'Aditya']) {
      await DeviceHub().callContact(alias);
      expect(calls.last.method, 'callContact');
      expect(calls.last.arguments, {'who': alias});
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  test(
      'completion allowlist keeps failures, recipient questions and mixed outcomes',
      () {
    for (final outcome in [
      "I couldn't place the call.",
      'Who should I call?',
      'Recipient confirmation cancelled. No call or WhatsApp draft was opened.',
      'Done.',
      'Media volume verified by two readbacks. 30%\nFailed',
      'Unknown response'
    ]) {
      expect(IntentRouter.completedCommandOutcome(outcome), false,
          reason: outcome);
    }
    expect(IntentRouter.completedCommandOutcome(''), true);
    expect(
        IntentRouter.completedCommandOutcome(
            'Opened the WhatsApp draft. Review the recipient and message, then tap Send in WhatsApp yourself.'),
        true);
    expect(
        IntentRouter.completedCommandOutcome(
            'Media volume verified by two readbacks. 30%'),
        true);
  });
  test('voice transcripts and typed call commands preserve custom nicknames',
      () async {
    for (final nickname in ['Mimi', 'Appa', 'Bro']) {
      final router = RecordingRouter()..outcome = '';
      final controller = FridayController(
          brain: NoBrain(),
          router: router,
          chatStore: MemoryStore(),
          speech: NoSpeech(),
          settings: Muted());
      await controller.send('call $nickname');
      expect(router.received.single.type, FridayActionType.callContact);
      expect(
          router.received.single.target.toLowerCase(), nickname.toLowerCase());
      controller.dispose();
    }
  });
}
