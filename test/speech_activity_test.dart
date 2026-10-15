import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friday/services/speech/speech_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<void> event(String method, [dynamic args]) async {
    final done = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
            'flutter_tts',
            const StandardMethodCodec()
                .encodeMethodCall(MethodCall(method, args)),
            (_) => done.complete());
    await done.future;
  }

  test('speaking visual state follows actual TTS callbacks', () async {
    final s = SpeechService();
    expect(s.activity.value, SpeechActivity.idle);
    await event('speak.onStart');
    expect(s.activity.value, SpeechActivity.speaking);
    await event('speak.onComplete');
    expect(s.activity.value, SpeechActivity.idle);
    await event('speak.onStart');
    await event('speak.onCancel');
    expect(s.activity.value, SpeechActivity.idle);
    await event('speak.onStart');
    await event('speak.onError', 'test error');
    expect(s.activity.value, SpeechActivity.idle);
  });
  test('failed platform speak/stop never leaves a simulated speaking state',
      () async {
    final s = SpeechService();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'),
            (c) async {
      throw PlatformException(code: 'unavailable');
    });
    await s.speak('Hello');
    expect(s.activity.value, SpeechActivity.idle);
    await event('speak.onStart');
    try {
      await s.stopSpeaking();
    } catch (_) {}
    expect(s.activity.value, SpeechActivity.idle);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'), null);
  });
  test('listening visual state follows recognition status, not a fake meter',
      () async {
    const channel = MethodChannel('plugin.csdcorp.com/speech_to_text');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async => true);
    final s = SpeechService();
    expect(await s.initSpeech(), isTrue);
    Future<void> status(String value) async {
      final done = Completer<void>();
      messenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec()
              .encodeMethodCall(MethodCall('notifyStatus', value)),
          (_) => done.complete());
      await done.future;
    }

    await status('listening');
    expect(s.activity.value, SpeechActivity.listening);
    await status('notListening');
    expect(s.activity.value, SpeechActivity.idle);
    messenger.setMockMethodCallHandler(channel, null);
  });
}
