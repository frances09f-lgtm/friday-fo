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

group('forgiving small-model drift (OpenJarvis-style)', () {
  test('accepts case-insensitive and spaced envelope keys', () {
    final r = parser.parse(
      '{"Reply":"Opening WhatsApp.","Action":{"Type":"open_app","App":"whatsapp"}}',
    );
    expect(r.reply, 'Opening WhatsApp.');
    expect(r.action.type, FridayActionType.openApp);
    expect(r.action.app, 'whatsapp');
  });

  test('accepts alternate reply keys from chat models', () {
    final r = parser.parse('{"response":"Hi there."}');
    expect(r.reply, 'Hi there.');
    final r2 = parser.parse('{"final_answer":"All done."}');
    expect(r2.reply, 'All done.');
  });

  test('normalizes drifting action type values', () {
    for (final variant in ['OpenApp', 'Open App', 'OPEN-APP', 'open app']) {
      final r = parser.parse(
        '{"reply":"ok","action":{"type":"$variant","app":"camera"}}',
      );
      expect(r.action.type, FridayActionType.openApp, reason: variant);
    }
  });

  test('accepts camelCase and numeric-string action fields', () {
    final r = parser.parse(
      '{"reply":"ok","action":{"type":"set_reminder","title":"stretch","afterMinutes":"30"}}',
    );
    expect(r.action.afterMinutes, 30);
    final v = parser.parse(
      '{"reply":"ok","action":{"type":"set_volume","target":50}}',
    );
    expect(v.action.target, '50');
  });

  test('takes the final answer from ReAct-style text, never its action', () {
    final r = parser.parse(
      'Thought: the user wants the torch on\nAction: torch_on\nFinal Answer: The torch is on.',
    );
    expect(r.reply, 'The torch is on.');
    expect(r.action.type, FridayActionType.none);
  });

  test('malformed JSON never produces an action', () {
    final r = parser.parse(
      '{"reply":"ok","action":{"type":"torch_on",}}',
    );
    expect(r.action.type, FridayActionType.none);
  });

  test('multi-part actions survive casing drift', () {
    final r = parser.parse(
      '{"Reply":"Doing both.","Actions":[{"Type":"Torch_Off"},{"Type":"open_app","APP":"camera"}]}',
    );
    expect(r.allActions.length, 2);
    expect(r.allActions[0].type, FridayActionType.torchOff);
    expect(r.allActions[1].type, FridayActionType.openApp);
    expect(r.allActions[1].app, 'camera');
  });
});
}
