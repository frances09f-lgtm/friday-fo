import 'package:flutter_test/flutter_test.dart';
import 'package:friday/models/friday_response.dart';
import 'package:friday/services/ai/offline_engine.dart';

void main() {
  test('whatsapp command routes to WhatsApp, never SMS', () {
    final r = const OfflineEngine()
        .handle('send a WhatsApp message to dad saying I am on my way');
    expect(r.action.type, FridayActionType.sendWhatsApp);
    expect(r.action.target, 'dad');
    expect(r.action.body, 'I am on my way');
  });

  test('bare whatsapp phrasing works too', () {
    final r = const OfflineEngine().handle('whatsapp aai saying jevan zala');
    expect(r.action.type, FridayActionType.sendWhatsApp);
    expect(r.action.target, 'aai');
    expect(r.action.body, 'jevan zala');
  });

  test('plain text/SMS still goes to SMS', () {
    final r = const OfflineEngine().handle('text dad saying hi');
    expect(r.action.type, FridayActionType.sendText);
    final r2 = const OfflineEngine().handle('send sms to mom saying ok');
    expect(r2.action.type, FridayActionType.sendText);
  });

  test('parser maps send_whatsapp from model json', () {
    final a = FridayAction.fromJson(
        {'type': 'send_whatsapp', 'target': 'mom', 'body': 'hi'});
    expect(a.type, FridayActionType.sendWhatsApp);
    expect(a.target, 'mom');
    expect(a.body, 'hi');
  });
}
