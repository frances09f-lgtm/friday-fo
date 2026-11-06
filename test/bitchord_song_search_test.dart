import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friday/services/ai/offline_engine.dart';
import 'package:friday/services/device/device_hub.dart';
import 'package:friday/models/friday_response.dart';
import 'package:friday/services/intent_router.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('song query retained literally in local parse', () {
    for (final q in ['Tum Ho', 'Tum Ho by Mohit Chauhan', 'नमो नमो']) {
      final r = const OfflineEngine().handle('play $q');
      expect(r.action.type, FridayActionType.playMusic);
      expect(r.action.query, q);
    }
    for (final q in ['play music', 'resume music']) {
      expect(const OfflineEngine().handle(q).action.query, isEmpty);
    }
    for (final q in [
      'play first video',
      'play music on Spotify',
      'play chess and send a message'
    ]) {
      expect(
          const OfflineEngine().handle(q).action.query, isNot('first video'));
    }
  });
  test('channel carries exact song query', () async {
    const channel = MethodChannel('friday/device');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'playMusic');
      expect(call.arguments, {'query': 'Tum Ho'});
      return 'bitchord_verified_song';
    });
    expect(
        await DeviceHub().playMusic(query: 'Tum Ho'), 'bitchord_verified_song');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  test('outcomes never confuse catalog ambiguity with playback', () {
    expect(IntentRouter.bitchordReply('bitchord_search_ambiguous'),
        contains('No song was selected'));
    expect(IntentRouter.bitchordReply('bitchord_song_unverified'),
        contains('Check BitChord before retrying'));
    expect(IntentRouter.bitchordReply('bitchord_verified_song'),
        contains('media ID and playback state'));
  });
  test('native query path cannot autoplay first search hit or generic fallback',
      () {
    final s = File(
            'android/app/src/main/kotlin/com/friday/assistant/BitChordSongSearch.kt')
        .readAsStringSync();
    expect(s, contains('BitChordSongPolicy.select'));
    expect(s, contains('b.isPlaying&&b.currentMediaItem?.mediaId==chosen.id'));
    expect(s, isNot(contains('INTENT_ACTION_MEDIA_PLAY_FROM_SEARCH')));
    expect(s, isNot(contains('startActivity')));
  });
}
