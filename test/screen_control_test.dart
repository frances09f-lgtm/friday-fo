import 'package:flutter_test/flutter_test.dart';
import 'package:friday/services/agent/agent_contract.dart';
import 'package:friday/services/agent/friday_agent.dart';
import 'package:friday/services/agent/workflow_planner.dart';

Map<String, dynamic> view(String pkg, List<Map<String, dynamic>> es) => {
      'success': true,
      'package': pkg,
      'elements': es,
      'token': 'new',
      'audioActive': true
    };
void main() {
  test('all requested app workflows parse without engine change', () {
    for (final spec in [
      ('Open YouTube and play GTA 6', 'play'),
      ('Open WhatsApp and open my chat with Rahul', 'contact'),
      ('Open ChatGPT and search for weather', 'question'),
      ('Open Instagram and search for Rahul', 'search')
    ]) expect(AgentGoal.parse(spec.$1)?.workflow, spec.$2);
  });
  test('read and compound controls parse and retain exact typing', () {
    expect(
        AgentGoal.parse('Tell me what is currently displayed on my screen')
            ?.workflow,
        'read');
    final g =
        AgentGoal.parse('Go back, scroll down, tap Search and type GTA 6')!;
    expect(g.commands.map((a) => a.action), ['back', 'scroll', 'tap', 'type']);
    expect(g.commands.last.text, 'GTA 6');
    expect(g.permits(AgentAction(action: 'type', text: 'different')), false);
  });
  test('WhatsApp cannot type message or submit send from screen instruction',
      () {
    final g = AgentGoal.parse('Open WhatsApp and open my chat with Rahul')!;
    expect(
        g.permits(AgentAction(action: 'tap', target: {'text': 'Send'})), false);
    expect(g.permits(AgentAction(action: 'type', text: 'hello')), false);
    expect(
        WorkflowPlanner.next(
            g,
            view(g.package, [
              {'text': 'Rahul', 'editable': false},
              {'text': 'Rahul', 'editable': false}
            ])),
        isNull);
  });
  test('playback evidence not search results or dispatch success', () {
    final g = AgentGoal.parse('Open YouTube and play GTA 6')!;
    expect(
        FridayAgent.complete(
            g,
            view(g.package, [
              {'text': 'GTA 6 official trailer'},
              {'text': 'Videos Results'}
            ])),
        false);
    expect(
        FridayAgent.complete(
            g,
            view(g.package, [
              {'text': 'GTA 6 official trailer'},
              {'contentDescription': 'Pause'}
            ])),
        true);
    expect(
        FridayAgent.complete(
            g,
            view('other', [
              {'text': 'GTA 6'},
              {'contentDescription': 'Pause'}
            ])),
        false);
  });
  test('ChatGPT requires question plus response or loading', () {
    final g = AgentGoal.parse('Open ChatGPT and ask explain gravity')!;
    expect(
        FridayAgent.complete(
            g,
            view(g.package, [
              {'text': g.query, 'editable': true},
              {'text': 'Thinking'}
            ])),
        false);
    expect(
        FridayAgent.complete(
            g,
            view(g.package, [
              {'text': g.query, 'editable': false},
              {'contentDescription': 'Stop generating'}
            ])),
        true);
    expect(
        FridayAgent.complete(
            g,
            view(g.package, [
              {'text': g.query, 'editable': false}
            ])),
        false);
  });
  test('contact completion needs exact header plus composer', () {
    final g = AgentGoal.parse('Open WhatsApp and open my chat with Rahul')!;
    expect(
        FridayAgent.complete(
            g,
            view(g.package, [
              {'text': 'Rahul'}
            ])),
        false);
    expect(
        FridayAgent.complete(
            g,
            view(g.package, [
              {
                'text': 'Rahul',
                'resourceId': 'com.whatsapp:id/conversation_contact_name'
              },
              {'resourceId': 'com.whatsapp:id/entry', 'editable': true}
            ])),
        true);
  });
  test('constrained recovery uses only unique semantic observed targets', () {
    final g = AgentGoal.parse('Open YouTube and search for GTA 6')!;
    final s = view(g.package, [
      {'contentDescription': 'Search', 'clickable': true}
    ]);
    expect(
        WorkflowPlanner.next(g, s)?.target, {'contentDescription': 'Search'});
    expect(
        WorkflowPlanner.next(
            g,
            view(g.package, [
              {'contentDescription': 'Search'},
              {'contentDescription': 'Search'}
            ])),
        isNull);
    expect(
        WorkflowPlanner.next(
            g,
            view(g.package, [
              {'text': 'Sign in'}
            ])),
        isNull);
  });
  test('question submit only proposed after exact composer text', () {
    final g = AgentGoal.parse('Open ChatGPT and ask gravity')!;
    final a = WorkflowPlanner.next(
        g,
        view(g.package, [
          {'resourceId': 'composer', 'editable': true, 'text': 'gravity'},
          {'contentDescription': 'Send prompt'}
        ]));
    expect(a?.action, 'submit');
    expect(a?.text, g.query);
  });
}
