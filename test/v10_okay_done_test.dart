import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:friday/models/friday_response.dart';
import 'package:friday/services/ai/ai_brain.dart';
import 'package:friday/services/ai/local_model_service.dart';
import 'package:friday/services/device/device_hub.dart';
import 'package:friday/services/device/reminder_service.dart';
import 'package:friday/services/intent_router.dart';
import 'package:friday/services/speech/speech_service.dart';
import 'package:friday/services/storage/chat_store.dart';
import 'package:friday/services/storage/settings_store.dart';
import 'package:friday/state/friday_controller.dart';

class _FakeBrain extends AIBrain {
  _FakeBrain(SettingsStore settings, this._response)
      : super(settings: settings, local: LocalModelService());
  final FridayResponse _response;
  @override
  Future<FridayResponse> ask(String userText,
          {List<dynamic> history = const []}) async =>
      _response;
}

class _FakeRouter extends IntentRouter {
  _FakeRouter() : super(deviceHub: DeviceHub(), reminders: ReminderService());
  String outcome = '';
  int calls = 0;
  @override
  Future<String> executeAll(List<FridayAction> actions) async {
    calls++;
    return outcome;
  }
}

class _FakeSpeech extends SpeechService {
  final List<String> spoken = [];
  @override
  Future<void> speak(String text, {String locale = 'en-IN'}) async {
    spoken.add(text);
  }
}

Future<FridayController> _controller(
    FridayResponse response, _FakeRouter router, _FakeSpeech speech,
    {bool speak = false}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final settings = SettingsStore(const FlutterSecureStorage(), prefs);
  settings.speakReplies = speak;
  return FridayController(
    brain: _FakeBrain(settings, response),
    router: router,
    chatStore: ChatStore(prefs),
    speech: speech,
    settings: settings,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('action command: Okay on accept, Done plus outcome lines on finish',
      () async {
    final router = _FakeRouter()..outcome = 'Volume set to 40%';
    final speech = _FakeSpeech();
    final c = await _controller(
        FridayResponse(
          reply: 'Setting volume.',
          action: const FridayAction(
              type: FridayActionType.setVolume, target: '40'),
        ),
        router,
        speech);
    await c.send('set volume 40');
    expect(router.calls, 1);
    final texts = c.messages.map((m) => m.text).toList();
    expect(texts, ['set volume 40', 'Okay.', 'Volume set to 40%']);
  });

  test('multi-part command: one Okay, one Done, every outcome line kept',
      () async {
    final router = _FakeRouter()
      ..outcome = 'Flashlight turned off.\nOpened Camera.';
    final speech = _FakeSpeech();
    final c = await _controller(
        FridayResponse(
          reply: 'On it.',
          action: const FridayAction(type: FridayActionType.torchOff),
          extraActions: const [
            FridayAction(type: FridayActionType.openApp, app: 'camera')
          ],
        ),
        router,
        speech);
    await c.send('flashlight off and open camera');
    final texts = c.messages.map((m) => m.text).toList();
    expect(texts, [
      'flashlight off and open camera',
      'Okay.',
      'Flashlight turned off.\nOpened Camera.'
    ]);
  });

  test('plain conversation gets no okay/done wrapper', () async {
    final router = _FakeRouter();
    final speech = _FakeSpeech();
    final c = await _controller(
        FridayResponse(reply: 'I am fine, thanks!'), router, speech);
    await c.send('how are you');
    expect(router.calls, 0);
    final texts = c.messages.map((m) => m.text).toList();
    expect(texts, ['how are you', 'I am fine, thanks!']);
  });

  test('spoken replies: Okay first, then the done line', () async {
    final router = _FakeRouter()..outcome = 'Volume set to 40%';
    final speech = _FakeSpeech();
    final c = await _controller(
        FridayResponse(
          reply: 'Setting volume.',
          action: const FridayAction(
              type: FridayActionType.setVolume, target: '40'),
        ),
        router,
        speech,
        speak: true);
    await c.send('set volume 40');
    expect(speech.spoken, ['Okay.', 'Volume set to 40%']);
  });
  test('unexpected execution error clears busy without false Done', () async {
    final router = _ThrowRouter();
    final c = await _controller(
        const FridayResponse(
            reply: 'Working',
            action:
                FridayAction(type: FridayActionType.openApp, app: 'camera')),
        router,
        _FakeSpeech());
    await c.send('open camera');
    expect(c.busy, false);
    expect(c.messages.last.text, contains('may already have happened'));
    expect(c.messages.last.text, isNot(contains('Done')));
    await c.send('open camera');
    expect(c.busy, false);
  });
}

class _ThrowRouter extends _FakeRouter {
  @override
  Future<String> executeAll(List<FridayAction> actions) async =>
      throw StateError('execution failure');
}
