import 'package:flutter_test/flutter_test.dart';
import 'package:friday/models/chat_message.dart';
import 'package:friday/services/ai/local_model_service.dart';
import 'package:friday/services/agent/agent_contract.dart';
import 'package:friday/services/agent/friday_agent.dart';

const command = 'Open WhatsApp and open my chat with Rahul';
const wa = 'com.whatsapp';
Map<String, dynamic> screen(String token, List<Map<String, dynamic>> elements,
        {String package = wa}) =>
    {
      'success': true,
      'package': package,
      'token': token,
      'eventRevision': 1,
      'elements': elements
    };

class RejectingModel extends LocalModelService {
  int calls = 0;
  @override
  Future<String> generate(
      {required String system,
      required String userText,
      List<ChatMessage> history = const []}) async {
    calls++;
    return 'not an action';
  }
}

class ChatDevice implements AgentDevice {
  int index = 0;
  final List<Map<String, dynamic>> screens;
  final actions = <Map<String, dynamic>>[];
  ChatDevice(this.screens);
  @override
  Future<Map<String, dynamic>> call(String method,
      [Map<String, dynamic> args = const {}]) async {
    if (method == 'start') return {'success': true, 'package': wa};
    if (method == 'observe' || method == 'await_screen') return screens[index];
    if (method == 'act') {
      final a = Map<String, dynamic>.from(args['action']);
      actions.add(a);
      if (a['action'] != 'wait' && index < screens.length - 1) index++;
    }
    return {'success': true};
  }
}

void main() {
  final goal = AgentGoal.parse(command)!;
  test('exact screenshot command is parsed as exact contact navigation', () {
    expect(goal.package, wa);
    expect(goal.workflow, 'contact');
    expect(goal.query, 'Rahul');
  });

  test('exact command opens, searches and verifies chat without model output',
      () async {
    final model = RejectingModel();
    final device = ChatDevice([
      screen('friday', [], package: 'com.friday.assistant'),
      screen('list', [
        {'contentDescription': 'Search', 'clickable': true}
      ]),
      screen('search', [
        {
          'resourceId': 'com.whatsapp:id/search_src_text',
          'editable': true,
          'focused': true,
          'text': ''
        }
      ]),
      screen('results', [
        {
          'resourceId': 'com.whatsapp:id/search_src_text',
          'editable': true,
          'focused': true,
          'text': 'Rahul'
        },
        {
          'resourceId': 'com.whatsapp:id/contact_name',
          'text': 'Rahul',
          'clickable': true
        },
      ]),
      screen('chat', [
        {
          'resourceId': 'com.whatsapp:id/conversation_contact_name',
          'text': 'Rahul'
        },
        {'resourceId': 'com.whatsapp:id/entry', 'editable': true, 'text': ''},
      ]),
    ]);
    final agent = FridayAgent(brain: LocalBrain(model), device: device);
    await agent.start(command);
    expect(agent.result, 'Done');
    expect(model.calls, 0);
    expect(device.actions.map((a) => a['action']),
        ['open_app', 'tap', 'type', 'tap']);
    expect(device.actions[2]['text'], 'Rahul');
    expect(agent.rejectedOutput, isEmpty);
  });

  test('unreadable WhatsApp controls wait instead of invoking malformed model',
      () async {
    final model = RejectingModel();
    final action =
        await LocalBrain(model).decide(goal, screen('loading', []), []);
    expect(action.action, 'wait');
    expect(model.calls, 0);
  });

  test('missing controls stop after two observation waits with a useful reason',
      () async {
    final model = RejectingModel();
    final device = ChatDevice([screen('loading', [])]);
    final agent = FridayAgent(brain: LocalBrain(model), device: device);
    await agent.start(command);
    expect(model.calls, 0);
    expect(device.actions.map((a) => a['action']), ['wait', 'wait']);
    expect(agent.result, contains('could not be verified'));
    expect(agent.result, isNot(contains('Local model output rejected')));
    expect(agent.result, isNot('Done'));
  });

  test('a loading screen can become readable on the next observation',
      () async {
    final model = RejectingModel();
    final brain = LocalBrain(model);
    expect(
        (await brain.decide(goal, screen('loading', []), [])).action, 'wait');
    final action = await brain.decide(
        goal,
        screen('list', [
          {'contentDescription': 'Search', 'clickable': true}
        ]),
        ['Step 1 wait: verified']);
    expect(action.action, 'tap');
    expect(action.target['contentDescription'], 'Search');
    expect(model.calls, 0);
  });

  test('duplicate search controls require help without guessing', () async {
    final model = RejectingModel();
    final action = await LocalBrain(model).decide(
        goal,
        screen('duplicate', [
          {'contentDescription': 'Search', 'clickable': true},
          {'contentDescription': 'Search', 'clickable': true},
        ]),
        []);
    expect(action.action, 'ask_confirmation');
    expect(action.reason, contains('Several WhatsApp search controls'));
    expect(model.calls, 0);
  });

  test('protected permission screen remains blocked without LLM fallback',
      () async {
    final model = RejectingModel();
    final action = await LocalBrain(model).decide(
        goal,
        screen('permission', [
          {'text': 'Allow permission', 'clickable': true},
          {'contentDescription': 'Search', 'clickable': true},
        ]),
        []);
    expect(action.action, 'ask_confirmation');
    expect(action.reason, contains('Complete it yourself'));
    expect(model.calls, 0);
  });

  test('duplicate Rahul search results remain ambiguous', () async {
    final model = RejectingModel();
    final action = await LocalBrain(model).decide(
        goal,
        screen('duplicates', [
          {
            'resourceId': 'search',
            'editable': true,
            'focused': true,
            'text': 'Rahul'
          },
          {'text': 'Rahul'},
          {'text': 'Rahul'},
        ]),
        []);
    expect(action.action, 'ask_confirmation');
    expect(model.calls, 0);
  });

  test('WhatsApp composer cannot become a search field or receive text',
      () async {
    final model = RejectingModel();
    final action = await LocalBrain(model).decide(
        goal,
        screen('other_chat', [
          {
            'resourceId': 'com.whatsapp:id/entry',
            'editable': true,
            'focused': true,
            'text': ''
          },
          {'contentDescription': 'Send', 'clickable': true},
        ]),
        []);
    expect(action.action, 'wait');
    expect(model.calls, 0);
    expect(
        goal.permits(
            AgentAction(action: 'tap', target: {'contentDescription': 'Send'})),
        false);
  });

  test(
      'strict action validation still rejects coordinates, malformed and unknown output',
      () {
    for (final raw in [
      'garbage',
      '[]',
      '{"action":"erase"}',
      '{"action":"tap","x":12,"y":20}',
      '{"action":"tap","target":{"x":12,"y":20}}',
      '{"action":"tap","confidence":"high"}'
    ]) {
      expect(() => AgentAction.parse(raw), throwsFormatException);
    }
  });

  test('nonrecipe model path still rejects malformed output', () async {
    final model = RejectingModel();
    const youtube = AgentGoal('custom', 'example.custom', 'cats');
    await expectLater(
        LocalBrain(model).decide(
            youtube, screen('unknown', [], package: youtube.package), []),
        throwsA(isA<AgentOutputFailure>()));
    expect(model.calls, 3);
  });
}
