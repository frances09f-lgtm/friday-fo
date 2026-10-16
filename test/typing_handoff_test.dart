import 'package:flutter_test/flutter_test.dart';
import 'package:friday/services/agent/agent_contract.dart';
import 'package:friday/services/agent/friday_agent.dart';
import 'package:friday/services/agent/workflow_planner.dart';

Map<String, dynamic> screen(String pkg, List<Map<String, dynamic>> es) =>
    {'success': true, 'package': pkg, 'elements': es, 'token': 'new'};
Map<String, dynamic> field(String text,
        {String id = 'input',
        String desc = '',
        String hint = '',
        bool focus = true}) =>
    {
      'text': text,
      'resourceId': id,
      'contentDescription': desc,
      'hintText': hint,
      'editable': true,
      'focused': focus,
      'clickable': true
    };
void main() {
  test('ChatGPT visible Send label survives empty content description', () {
    final g = AgentGoal.parse('Open ChatGPT and search for explain gravity')!;
    final a = WorkflowPlanner.next(
        g,
        screen(g.package, [
          field(g.query),
          {
            'text': 'Send',
            'contentDescription': '',
            'resourceId': 'send_button',
            'clickable': true
          }
        ]));
    expect(a?.action, 'submit');
  });
  test('ChatGPT focuses its unique editor before writing', () {
    final g = AgentGoal.parse('Open ChatGPT and search for explain gravity')!;
    expect(
        WorkflowPlanner.next(
                g, screen(g.package, [field('', id: 'composer', focus: false)]))
            ?.action,
        'tap');
  });
  for (final pkg in [
    'com.whatsapp',
    'com.google.android.youtube',
    'com.instagram.android'
  ]) {
    test('$pkg keeps recognizing Search hint after typing replaces placeholder',
        () {
      final g = AgentGoal('', pkg, 'Rahul');
      final a = WorkflowPlanner.next(
          g, screen(pkg, [field('Rahul', hint: 'Search')]));
      expect(a, isNotNull);
      expect(a!.action, pkg == 'com.whatsapp' ? 'wait' : 'submit');
    });
  }
  test('hint-only search target stays scoped and must be focused', () {
    final g = AgentGoal('', 'com.instagram.android', 'gravity');
    final a = WorkflowPlanner.next(g,
        screen(g.package, [field('', id: '', hint: 'Search', focus: false)]));
    expect(a?.action, 'tap');
    expect(a?.target['hintText'], 'Search');
    expect(g.permits(a!), true);
    expect(
        FridayAgent.verify(
            a, screen(g.package, [field('', id: '', hint: 'Search')])),
        true);
    expect(
        FridayAgent.verify(
            a, screen('com.keyboard', [field('', id: '', hint: 'Search')])),
        false);
  });
  test('Chrome recognizes query field by address hint', () {
    final g = AgentGoal('', 'com.android.chrome', 'gravity');
    expect(
        WorkflowPlanner.next(
            g,
            screen(g.package,
                [field(g.query, hint: 'Search or type web address')]))?.action,
        'submit');
  });
  test('typing verification accepts changed description on same stable view ID',
      () {
    final a = AgentAction(
        action: 'type',
        text: 'Rahul',
        target: {'resourceId': 'search', 'contentDescription': 'Search'},
        expect: {'package': 'com.whatsapp', 'textEquals': 'Rahul'});
    expect(
        FridayAgent.verify(
            a,
            screen(
                'com.whatsapp', [field('Rahul', id: 'search', desc: 'Rahul')])),
        true);
    expect(
        FridayAgent.verify(
            a,
            screen('com.whatsapp',
                [field('Rahul', id: 'composer', desc: 'Rahul')])),
        false);
    expect(
        FridayAgent.verify(
            a, screen('com.other', [field('Rahul', id: 'search')])),
        false);
    expect(
        FridayAgent.verify(
            a,
            screen('com.whatsapp', [
              field('Rahul', id: 'search'),
              field('different', id: 'search')
            ])),
        false);
  });
  test(
      'manual typing can target an exact observed hint, not keyboard coordinates',
      () {
    final a = FridayAgent.commandAction(
        AgentAction(action: 'type', text: 'gravity'),
        screen('com.example.notes', [field('', id: '', hint: 'Note text')]),
        'com.example.notes');
    expect(a.target, {'hintText': 'Note text'});
    expect(
        FridayAgent.verify(
            a,
            screen('com.example.notes',
                [field('gravity', id: '', hint: 'Note text')])),
        true);
    expect(
        FridayAgent.verify(
            a,
            screen(
                'com.keyboard', [field('gravity', id: '', hint: 'Note text')])),
        false);
  });
  test('focus verification uses the unique stable field when its label changes',
      () {
    final a = AgentAction(
        action: 'tap',
        target: {'resourceId': 'search', 'contentDescription': 'Search'},
        expect: {'package': 'com.whatsapp', 'editable': true, 'focused': true});
    expect(
        FridayAgent.verify(
            a,
            screen('com.whatsapp',
                [field('', id: 'search', desc: 'Type to search')])),
        true);
    expect(
        FridayAgent.verify(
            a,
            screen('com.whatsapp', [
              field('', id: 'search'),
              field('', id: 'search', focus: false)
            ])),
        false);
    expect(
        FridayAgent.verify(
            a, screen('com.keyboard', [field('', id: 'search')])),
        false);
  });
  test('without stable ID changed description is not accepted', () {
    final a = AgentAction(
        action: 'type',
        text: 'Rahul',
        target: {'contentDescription': 'Search'},
        expect: {'package': 'com.whatsapp', 'textEquals': 'Rahul'});
    expect(
        FridayAgent.verify(
            a, screen('com.whatsapp', [field('Rahul', id: '', desc: 'Rahul')])),
        false);
  });
  test('real nonempty Send description is not replaced by visible text', () {
    final g = AgentGoal.parse('Open ChatGPT and search for explain gravity')!;
    expect(
        WorkflowPlanner.next(
            g,
            screen(g.package, [
              field(g.query),
              {
                'text': 'Send',
                'contentDescription': 'Delete',
                'resourceId': 'x'
              }
            ])),
        null);
  });
}
