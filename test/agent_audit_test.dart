import 'package:flutter_test/flutter_test.dart';
import 'package:friday/services/agent/agent_contract.dart';
import 'package:friday/services/agent/friday_agent.dart';
import 'package:friday/services/agent/workflow_planner.dart';

Map<String, dynamic> scene(String p, List<Map<String, dynamic>> es,
        {String token = 'a'}) =>
    {'success': true, 'package': p, 'token': token, 'elements': es};
Map<String, dynamic> node(String text, String id,
        {bool edit = false, bool focus = false, bool click = true}) =>
    {
      'text': text,
      'resourceId': id,
      'editable': edit,
      'focused': focus,
      'clickable': click,
      'bounds': [0, 100, 300, 150]
    };
const wa = 'com.whatsapp';
void main() {
  for (final task in [
    'WhatsApp open chat search rahul',
    'Open WhatsApp and search Rahul chat',
    'Open WhatsApp and open chat with Rahul'
  ]) {
    test('contact wording: $task', () {
      final g = AgentGoal.parse(task);
      expect(g, isNotNull);
      expect(g!.workflow, 'contact');
      expect(g.query.toLowerCase(), 'rahul');
    });
  }
  test('known navigation does not require model download', () {
    for (final task in [
      'Open WhatsApp and open my chat with Rahul',
      'Open Settings and open Bluetooth',
      'Open YouTube and play cats',
      'Open Instagram and search Rahul'
    ]) {
      expect(AgentGoal.parse(task)!.noPlanner, true, reason: task);
    }
  });
  test('Bluetooth deterministic opening has a page postcondition', () {
    final g = AgentGoal.parse('Open Settings and open Bluetooth')!;
    final a = WorkflowPlanner.next(g,
        scene(g.package, [node('Bluetooth', 'com.android.settings:id/title')]));
    expect(a?.action, 'tap');
    expect(g.permits(a!), true);
    expect(a.expect['settingsPage'], true);
  });
  test('WhatsApp leaves wrong conversation before global search', () {
    final g = AgentGoal.parse('Open WhatsApp and open my chat with Rahul')!;
    final a = WorkflowPlanner.next(
        g,
        scene(wa, [
          node('Priya', 'conversation_contact_name'),
          node('', 'entry', edit: true)
        ]));
    expect(a?.action, 'back');
    expect(g.permits(a!), true);
  });
  test('command scroll carries exact observed container bounds', () {
    final a = FridayAgent.commandAction(
        AgentAction(action: 'scroll', text: 'down'),
        scene(wa, [
          {
            'scrollable': true,
            'bounds': [0, 0, 300, 600],
            'resourceId': 'chat_list'
          }
        ]),
        wa);
    expect(a.target['bounds'], [0, 0, 300, 600]);
  });
  test('failed observation cannot complete a task', () {
    final g = AgentGoal.parse('Open Chrome and search cats')!;
    expect(
        FridayAgent.complete(g, {
          'success': false,
          'package': g.package,
          'elements': [node('https://www.google.com/search?q=cats', 'url_bar')]
        }),
        false);
  });
}
