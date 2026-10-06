import 'package:flutter_test/flutter_test.dart';
import 'package:friday/models/friday_response.dart';
import 'package:friday/services/ai/offline_engine.dart';

void main() {
  const engine = OfflineEngine();
  final now = DateTime(2026, 10, 6, 22, 0);

  test('open command parses app name', () {
    final r = engine.handle('Open WhatsApp', now: now);
    expect(r.action.type, FridayActionType.openApp);
    expect(r.action.app, 'whatsapp');
    expect(r.source, FridaySource.offline);
  });

  test('open handles please and punctuation', () {
    final r = engine.handle('friday, please launch youtube.', now: now);
    expect(r.action.type, FridayActionType.openApp);
    expect(r.action.app, 'youtube');
  });

  test('read messages with no query', () {
    final r = engine.handle('read my messages', now: now);
    expect(r.action.type, FridayActionType.readMessages);
    expect(r.action.query, '');
  });

  test('read messages with a sender query', () {
    final r = engine.handle('check messages from Aditya', now: now);
    expect(r.action.type, FridayActionType.readMessages);
    expect(r.action.query, 'aditya');
  });

  test('reminder in minutes', () {
    final r = engine.handle('Remind me to stretch in 30 minutes', now: now);
    expect(r.action.type, FridayActionType.setReminder);
    expect(r.action.title, 'stretch');
    expect(r.action.afterMinutes, 30);
  });

  test('reminder in hours converts to minutes', () {
    final r = engine.handle('remind me to call Aditya in 2 hours', now: now);
    expect(r.action.afterMinutes, 120);
  });

  test('reminder at a time today', () {
    final r = engine.handle('remind me to take meds at 11:30 pm', now: now);
    expect(r.action.type, FridayActionType.setReminder);
    expect(r.action.afterMinutes, 90);
  });

  test('reminder at a past time rolls to tomorrow', () {
    final r = engine.handle('remind me to stretch at 9 am', now: now);
    expect(r.action.afterMinutes, 11 * 60);
  });

  test('plain question falls back gracefully', () {
    final r = engine.handle('what is the capital of France', now: now);
    expect(r.action.type, FridayActionType.none);
    expect(r.source, FridaySource.offline);
    expect(r.reply, contains('open an app'));
  });

  group('device controls route locally', () {
    test('flashlight on/off', () {
      const e = OfflineEngine();
      expect(e.handle('flashlight on').action.type, FridayActionType.torchOn);
      expect(e.handle('turn the torch off').action.type, FridayActionType.torchOff);
    });
    test('volume up/down', () {
      const e = OfflineEngine();
      expect(e.handle('increase volume').action.type, FridayActionType.volumeUp);
      expect(e.handle('turn the volume down').action.type, FridayActionType.volumeDown);
    });
    test('wifi and bluetooth open panels', () {
      const e = OfflineEngine();
      expect(e.handle('turn wifi off').action.type, FridayActionType.wifiSettings);
      expect(e.handle('bluetooth on').action.type, FridayActionType.bluetoothSettings);
    });
    test('device commands never fall through to the cloud fallback', () {
      const e = OfflineEngine();
      for (final c in ['flashlight on', 'increase volume', 'wifi off', 'bluetooth off']) {
        expect(e.handle(c).reply, isNot(contains("couldn't reach the cloud")));
      }
    });
  });
}

