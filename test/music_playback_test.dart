import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friday/models/friday_response.dart';
import 'package:friday/services/ai/offline_engine.dart';
import 'package:friday/services/ai/friday_parser.dart';
import 'package:friday/services/device/device_hub.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('play/resume routes locally to media playback, never generic app launch',
      () {
    for (final words in [
      'Play music',
      'Friday, please play music',
      'resume my music',
      'start music',
      'play music please',
      'resume playback'
    ]) {
      expect(const OfflineEngine().handle(words).action.type,
          FridayActionType.playMusic);
    }
    expect(const OfflineEngine().handle('open music').action.type,
        FridayActionType.openApp);
    expect(
        const FridayParser()
            .parse('{"reply":"ok","action":{"type":"play_music"}}')
            .action
            .type,
        FridayActionType.playMusic);
  });
  test(
      'native play uses Play rather than toggle and does not select an arbitrary app',
      () {
    final native = File(
            'android/app/src/main/kotlin/com/friday/assistant/MusicPlayback.kt')
        .readAsStringSync();
    expect(native, contains('KEYCODE_MEDIA_PLAY'));
    expect(native, isNot(contains('KEYCODE_MEDIA_PLAY_PAUSE')));
    expect(native, isNot(contains('startActivity')));
    expect(native, contains('audio.isMusicActive'));
    expect(
        File('android/app/src/main/kotlin/com/friday/assistant/DeviceBridge.kt')
            .readAsStringSync(),
        contains('"playMusic" -> MusicPlayback.resume'));
  });
  test(
      'device channel reports measured state and does not turn request into success',
      () async {
    const channel = MethodChannel('friday/device');
    for (final outcome in ['playing', 'requested', 'error']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'playMusic');
        return outcome;
      });
      expect(await DeviceHub().playMusic(), outcome);
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
}
