import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friday/models/friday_response.dart';
import 'package:friday/services/ai/offline_engine.dart';
import 'package:friday/services/ai/friday_parser.dart';
import 'package:friday/services/device/device_hub.dart';

void main() {
  test('audio writes have required permission and no preexisting audio Done',
      () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('android.permission.MODIFY_AUDIO_SETTINGS'));
    final music = File(
            'android/app/src/main/kotlin/com/friday/assistant/MusicPlayback.kt')
        .readAsStringSync();
    expect(music, contains('SpotifySessionControl.execute'));
    expect(music, isNot(contains('dispatchMediaKeyEvent')));
    final router = File('lib/services/intent_router.dart').readAsStringSync();
    expect(router, contains('No new playback change verified'));
    expect(router, contains('verifiedVolumeStep'));
  });
  test('verified volume channel returns measured state, not empty Done',
      () async {
    const c = MethodChannel('friday/device');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(c, (call) async {
      expect(call.method, 'volumeStepVerified');
      return 'Media volume did not change (5/15).';
    });
    expect(
        await DeviceHub().verifiedVolumeStep(true), contains('did not change'));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(c, null);
  });
  test('volume readback and overlay brightness permission are verified', () {
    final native =
        File('android/app/src/main/kotlin/com/friday/assistant/DeviceBridge.kt')
            .readAsStringSync();
    expect(native,
        contains('getStreamVolume(AudioManager.STREAM_MUSIC) == target'));
    expect(native, contains('== next && next != cur'));
    expect(native,
        contains('early==target&&after==target&&after!=before&&sameRoute'));
    final brightness = native.substring(
        native.indexOf('private fun setBrightnessPercent'),
        native.indexOf('private fun readSms'));
    expect(brightness, isNot(contains('if (activity != null)')));
    expect(brightness, contains('Settings.ACTION_MANAGE_WRITE_SETTINGS'));
    expect(brightness, contains('wrote && Settings.System.getInt'));
  });
  TestWidgetsFlutterBinding.ensureInitialized();
  test('next previous stop are local exact media actions', () {
    for (final entry in {
      'next music': FridayActionType.nextMusic,
      'previous music': FridayActionType.previousMusic,
      'stop music': FridayActionType.stopMusic
    }.entries) {
      expect(const OfflineEngine().handle(entry.key).action.type, entry.value);
    }
    final native = File(
            'android/app/src/main/kotlin/com/friday/assistant/MusicPlayback.kt')
        .readAsStringSync();
    expect(native,
        contains('SpotifySessionControl.execute(context,command,result)'));
  });
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
    expect(native,
        contains('SpotifySessionControl.execute(context,"play",result)'));
    expect(native, isNot(contains('KEYCODE_MEDIA_PLAY_PAUSE')));
    expect(native, isNot(contains('startActivity')));
    expect(native, isNot(contains('dispatchMediaKeyEvent')));
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
