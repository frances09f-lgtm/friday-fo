import 'package:flutter_test/flutter_test.dart';
import 'package:friday/models/friday_response.dart';
import 'package:friday/services/ai/friday_parser.dart';
import 'package:friday/services/ai/offline_engine.dart';

void main() {
  test('offline: brightness and volume in one utterance keep their own values', () {
    final r = const OfflineEngine().handle('set brightness 50 and volume 20');
    expect(r.allActions.length, 2);
    expect(r.allActions[0].type, FridayActionType.setBrightness);
    expect(r.allActions[0].target, '50');
    expect(r.allActions[1].type, FridayActionType.setVolume);
    expect(r.allActions[1].target, '20');
  });

  test('offline: volume-first order is preserved', () {
    final r = const OfflineEngine().handle('set volume 20 and brightness 50');
    expect(r.allActions[0].type, FridayActionType.setVolume);
    expect(r.allActions[1].type, FridayActionType.setBrightness);
  });

  test('offline: single volume command still one action', () {
    final r = const OfflineEngine().handle('set volume 30%');
    expect(r.allActions.length, 1);
    expect(r.allActions.single.type, FridayActionType.setVolume);
  });

  test('parser: actions array from model json', () {
    const raw = '{"reply":"Setting brightness to 50% and volume to 20%.",'
        '"actions":[{"type":"set_brightness","target":"50"},'
        '{"type":"set_volume","target":"20"}]}';
    final r = const FridayParser().parse(raw);
    expect(r.allActions.length, 2);
    expect(r.allActions[0].type, FridayActionType.setBrightness);
    expect(r.allActions[0].target, '50');
    expect(r.allActions[1].type, FridayActionType.setVolume);
    expect(r.allActions[1].target, '20');
  });

  test('parser: single action json stays one action', () {
    const raw = '{"reply":"Setting volume.","action":{"type":"set_volume","target":"30"}}';
    final r = const FridayParser().parse(raw);
    expect(r.allActions.length, 1);
    expect(r.action.type, FridayActionType.setVolume);
  });

  test('parser: no action yields none only', () {
    final r = const FridayParser().parse('{"reply":"Hi!","action":{"type":"none"}}');
    expect(r.allActions.length, 1);
    expect(r.allActions.single.type, FridayActionType.none);
  });
}
