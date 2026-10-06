import 'package:flutter_test/flutter_test.dart';
import 'package:friday/models/friday_response.dart';
import 'package:friday/services/ai/offline_engine.dart';

void main() {
  test('set volume to an exact percent routes offline', () {
    final r = const OfflineEngine().handle('set volume 30%');
    expect(r.action.type, FridayActionType.setVolume);
    expect(r.action.target, '30');
  });

  test('volume percent clamps above 100', () {
    final r = const OfflineEngine().handle('volume 250');
    expect(r.action.type, FridayActionType.setVolume);
    expect(r.action.target, '100');
  });

  test('brightness percent routes offline', () {
    final r = const OfflineEngine().handle('brightness 40%');
    expect(r.action.type, FridayActionType.setBrightness);
    expect(r.action.target, '40');
  });

  test('increase volume still routes to volume up, not percent', () {
    final r = const OfflineEngine().handle('increase volume');
    expect(r.action.type, FridayActionType.volumeUp);
  });

  test('parses set_volume and set_brightness from model json', () {
    final v = FridayAction.fromJson({'type': 'set_volume', 'target': '30'});
    expect(v.type, FridayActionType.setVolume);
    final b = FridayAction.fromJson({'type': 'set_brightness', 'target': '40'});
    expect(b.type, FridayActionType.setBrightness);
  });
}
