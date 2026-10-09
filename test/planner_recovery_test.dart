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
  test('app workflow cannot close target through model back or home', () {
    final g = AgentGoal.parse('open YouTube and play GTA 6')!;
    expect(g.permits(AgentAction(action: 'back', confidence: 1)), false);
    expect(g.permits(AgentAction(action: 'home', confidence: 1)), false);
    expect(
        AgentGoal.parse('Go back')!
            .permits(AgentAction(action: 'back', confidence: 1)),
        true);
  });
  test(
      'generic resource ID retains semantic Search label across recovery gates',
      () async {
    final g = AgentGoal.parse(
        'open YouTube and search for free alternatives of jio hotstar')!;
    final a =
        await LocalBrain(Output('{"action":"tap","confidence":0}')).decide(g, {
      'package': g.package,
      'elements': [
        {
          'resourceId': 'com.google.android.youtube:id/menu_item',
          'contentDescription': 'Search',
          'clickable': true
        }
      ]
    }, []);
    expect(a.target, {
      'resourceId': 'com.google.android.youtube:id/menu_item',
      'contentDescription': 'Search'
    });
    expect(g.permits(a), true);
    expect(a.expect['package'], g.package);
  });
  test('semantic recovery does not hide protected text behind search ID',
      () async {
    final g = AgentGoal.parse(
        'open YouTube and search for free alternatives of jio hotstar')!;
    await expectLater(
        LocalBrain(Output('{"action":"tap","confidence":0}')).decide(g, {
          'package': g.package,
          'elements': [
            {'resourceId': 'search', 'text': 'Allow permission'}
          ]
        }, []),
        throwsA(isA<AgentOutputFailure>()));
  });
  test('phone ChatGPT commands separate app target from query', () {
    for (final entry in {
      'ask chatgpt how are you': 'how are you',
      'search new ai on chatgpt': 'new ai',
      'search for new ai in chat gpt': 'new ai',
      'ask Chat GPT explain gravity': 'explain gravity'
    }.entries) {
      final goal = AgentGoal.parse(entry.key)!;
      expect(goal.package, 'com.openai.chatgpt');
      expect(goal.workflow, 'question');
      expect(goal.query, entry.value);
    }
    expect(AgentGoal.parse('how are you'), isNull);
  });
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
