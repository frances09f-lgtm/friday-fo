import 'package:flutter_test/flutter_test.dart';
import 'package:friday/services/agent/agent_contract.dart';
import 'package:friday/services/agent/friday_agent.dart';
import 'package:friday/services/ai/local_model_service.dart';
import 'package:friday/models/chat_message.dart';

class Output extends LocalModelService {
  final String output;
  Output(this.output);
  @override
  Future<String> generate(
          {required String system,
          required String userText,
          List<ChatMessage> history = const []}) async =>
      output;
}

void main() {
  for (final raw in [
    '{"action":"tap","target":{"contentDescription":"Search"}}',
    '{"action":"tap","confidence":0}',
    '{"action":"tap","confidence":0.2}',
    '{"action":"tap","confidence":1,"target":{"text":"Send"}}'
  ]) {
    test('invalid local decision recovers only unique observed search: $raw',
        () async {
      final g = AgentGoal.parse('open YouTube and search for GTA 6')!;
      final a = await LocalBrain(Output(raw)).decide(g, {
        'package': g.package,
        'elements': [
          {'contentDescription': 'Search', 'clickable': true}
        ]
      }, []);
      expect(a.action, 'tap');
      expect(a.target, {'contentDescription': 'Search'});
      expect(a.confidence, 1);
      expect(g.permits(a), true);
    });
  }
  test('missing confidence never grants an ambiguous click', () async {
    final g = AgentGoal.parse('open YouTube and search for GTA 6')!;
    await expectLater(
        LocalBrain(Output('{"action":"tap"}')).decide(g, {
          'package': g.package,
          'elements': [
            {'contentDescription': 'Search'},
            {'contentDescription': 'Search'}
          ]
        }, []),
        throwsA(isA<AgentOutputFailure>()));
  });
  test('typed-query recovery keeps exact user words and expected field',
      () async {
    final g = AgentGoal.parse('open YouTube and search for GTA 6')!;
    final a =
        await LocalBrain(Output('{"action":"type","confidence":0}')).decide(g, {
      'package': g.package,
      'elements': [
        {'resourceId': 'search_edit', 'editable': true, 'text': ''}
      ]
    }, []);
    expect(a.action, 'type');
    expect(a.text, 'GTA 6');
    expect(a.expect['textEquals'], 'GTA 6');
  });
}
