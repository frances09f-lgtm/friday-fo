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

  // v9: cross-domain combos (device control + app launch)
  for (final entry in {
    'flashlight off and open camera': [
      (FridayActionType.torchOff, ''),
      (FridayActionType.openApp, 'camera'),
    ],
    'set volume 40 and open WhatsApp': [
      (FridayActionType.setVolume, '40'),
      (FridayActionType.openApp, 'whatsapp'),
    ],
    'open camera and turn flashlight off': [
      (FridayActionType.openApp, 'camera'),
      (FridayActionType.torchOff, ''),
    ],
    'flashlight on and brightness 60': [
      (FridayActionType.torchOn, ''),
      (FridayActionType.setBrightness, '60'),
    ],
  }.entries) {
    final r = const OfflineEngine().handle(entry.key);
    test('offline multi: ${entry.key}', () {
      expect(r.allActions.length, entry.value.length, reason: entry.key);
      for (var i = 0; i < entry.value.length; i++) {
        expect(r.allActions[i].type, entry.value[i].$1, reason: entry.key);
        if (entry.value[i].$2.isNotEmpty) {
          expect(
              r.allActions[i].type == FridayActionType.openApp
                  ? r.allActions[i].app
                  : r.allActions[i].target,
              entry.value[i].$2,
              reason: entry.key);
        }
      }
    });
  }

  test('offline: single flashlight command stays single', () {
    final r = const OfflineEngine().handle('flashlight on');
    expect(r.allActions.length, 1);
    expect(r.allActions.single.type, FridayActionType.torchOn);
  });

  test('offline: single open stays single', () {
    final r = const OfflineEngine().handle('open whatsapp');
    expect(r.allActions.length, 1);
    expect(r.allActions.single.type, FridayActionType.openApp);
  });
}
