import 'package:flutter_test/flutter_test.dart';
import 'package:friday/models/friday_response.dart';
import 'package:friday/services/ai/friday_parser.dart';

void main() {
  const parser = FridayParser();

  test('parses a clean JSON envelope', () {
    final r = parser.parse(
      '{"reply":"Opening WhatsApp.","action":{"type":"open_app","app":"whatsapp"}}',
    );
    expect(r.reply, 'Opening WhatsApp.');
    expect(r.action.type, FridayActionType.openApp);
    expect(r.action.app, 'whatsapp');
    expect(r.source, FridaySource.cloud);
  });

  test('parses JSON wrapped in markdown fences and prose', () {
    final r = parser.parse(
      'Sure!\n```json\n{"reply":"Reminder set.","action":{"type":"set_reminder","title":"stretch","after_minutes":30}}\n```',
    );
    expect(r.action.type, FridayActionType.setReminder);
    expect(r.action.afterMinutes, 30);
  });

  test('falls back to raw text when there is no JSON', () {
    final r = parser.parse('The capital of France is Paris.');
    expect(r.reply, 'The capital of France is Paris.');
    expect(r.action.type, FridayActionType.none);
  });

  test('falls back to raw text on malformed JSON', () {
    final r = parser.parse('{"reply": broken');
    expect(r.reply, '{"reply": broken');
  });

  test('unknown action types are treated as none', () {
    final r = parser.parse(
      '{"reply":"Done.","action":{"type":"reboot_phone"}}',
    );
    expect(r.action.type, FridayActionType.none);
  });

  test('reminder payload round-trips', () {
    final r = parser.parse(
      '{"reply":"ok","action":{"type":"set_reminder","title":"x","after_minutes":5,"body":""}}',
    );
    expect(r.action.afterMinutes, 5);
  });
}
