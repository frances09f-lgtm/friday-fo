import 'package:flutter_test/flutter_test.dart';
import 'package:friday/models/friday_response.dart';
import 'package:friday/services/ai/offline_engine.dart';

void main() {
  test('routes a call by contact name offline', () {
    final r = const OfflineEngine().handle('call mom');
    expect(r.action.type, FridayActionType.callContact);
    expect(r.action.target, 'mom');
  });

  test('routes a call by phone number offline', () {
    final r = const OfflineEngine().handle('dial 9876543210');
    expect(r.action.type, FridayActionType.callContact);
    expect(r.action.target, '9876543210');
  });

  test('routes a text with message body offline', () {
    final r = const OfflineEngine().handle('text dad saying I am on my way');
    expect(r.action.type, FridayActionType.sendText);
    expect(r.action.target, 'dad');
    expect(r.action.body, 'I am on my way');
  });

  test('parses call_contact and send_text from model json', () {
    final call = FridayAction.fromJson({'type': 'call_contact', 'target': 'mom'});
    expect(call.type, FridayActionType.callContact);
    expect(call.target, 'mom');
    final sms = FridayAction.fromJson(
        {'type': 'send_text', 'target': 'dad', 'body': 'hi'});
    expect(sms.type, FridayActionType.sendText);
    expect(sms.body, 'hi');
  });

  test('read messages intent still wins over text pattern', () {
    final r = const OfflineEngine().handle('read my messages');
    expect(r.action.type, FridayActionType.readMessages);
  });
}
