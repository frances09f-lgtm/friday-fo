import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:friday/services/agent/agent_contract.dart';
import 'package:friday/services/agent/friday_agent.dart';
import 'package:friday/services/agent/screen_context.dart';
import 'package:friday/services/agent/workflow_planner.dart';

const pkg = 'com.google.android.youtube';
Map<String, dynamic> view(String token, List<Map<String, dynamic>> elements) =>
    {
      'success': true,
      'package': pkg,
      'token': token,
      'elements': elements,
      'eventRevision': 1,
    };

class NoBrain implements AgentBrain {
  @override
  Future<AgentAction> decide(
          AgentGoal g, Map<String, dynamic> s, List<String> h) async =>
      throw StateError('Commands must not invoke model');
}

class SettleDevice implements AgentDevice {
  final Map<String, dynamic> before;
  final List<Map<String, dynamic>> after;
  int acts = 0, waits = 0;
  bool acted = false;
  SettleDevice(this.before, this.after);
  @override
  Future<Map<String, dynamic>> call(String method,
      [Map<String, dynamic> args = const {}]) async {
    if (method == 'start') return {'success': true, 'package': pkg};
    if (method == 'observe') return acted ? after.last : before;
    if (method == 'act') {
      acts++;
      acted = true;
      return {'success': true};
    }
    if (method == 'await_screen') {
      waits++;
      if (after.length > 1) return after.removeAt(0);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      return after.single;
    }
    return {'success': true};
  }
}

void main() {
  test('goal context includes lower-tree relevant field and exact long labels',
      () {
    final elements = List.generate(
        100, (i) => <String, dynamic>{'id': 'root/$i', 'text': 'header $i'});
    elements[98] = {
      'id': 'root/98',
      'text': 'GTA 6 ' + 'x' * 120,
      'clickable': true,
      'bounds': [0, 400, 200, 450],
      'parentContext': 'result card'
    };
    elements[99] = {
      'id': 'root/99',
      'resourceId': 'search_box',
      'editable': true,
      'focused': true
    };
    final context = ScreenContext.forGoal(
        const AgentGoal('', pkg, 'GTA 6'), view('a', elements));
    final selected = context['elements'] as List;
    expect(selected.length, 40);
    expect(
        selected.any(
            (e) => e['id'] == 'root/98' && e['text'] == elements[98]['text']),
        true);
    expect(selected.any((e) => e['id'] == 'root/99'), true);
    expect(context['omittedCount'], 60);
    expect(context['truncated'], true);
  });
  test('production model context stays bounded without shortening labels', () {
    final elements = List.generate(
        100,
        (i) => <String, dynamic>{
              'id': 'root/$i',
              'text': 'header ' + 'x' * 150,
              'clickable': true
            });
    elements[99] = {
      'id': 'root/99',
      'resourceId': 'search_box',
      'editable': true,
      'focused': true,
      'text': ''
    };
    final c = ScreenContext.forGoal(
        const AgentGoal('', pkg, 'cats'), view('a', elements),
        maxChars: 1800);
    expect(jsonEncode(c).length, lessThanOrEqualTo(1800));
    expect((c['elements'] as List).any((e) => e['id'] == 'root/99'), true);
    expect(c['omittedCount'], 100 - (c['elements'] as List).length);
  });
  test(
      'missing labels remain explicit context not invented visual understanding',
      () {
    final c = ScreenContext.forGoal(
        const AgentGoal('', pkg, ''),
        view('a', [
          {'id': 'a', 'clickable': true, 'text': ''}
        ]));
    expect(c['truncated'], false);
    expect(c['observedCount'], 1);
    expect((c['elements'] as List).single['text'], isNull);
  });
  test('tap verifies transition not presence of vanished source label', () {
    final before = view('a', [
      {'text': 'Search'}
    ]);
    final a = FridayAgent.commandAction(
        AgentAction(action: 'tap', target: {'text': 'Search'}), before, pkg);
    expect(
        FridayAgent.verify(
            a,
            view('b', [
              {'editable': true, 'focused': true}
            ]),
            before: before),
        true);
    expect(FridayAgent.verify(a, before, before: before), false);
    expect(
        FridayAgent.verify(a, view('b', [])..['package'] = 'other',
            before: before),
        false);
  });
  test('back requires observed screen transition not any non-null token', () {
    final before = view('a', []);
    final a = AgentAction(action: 'back', expect: {'package': pkg});
    expect(FridayAgent.verify(a, before, before: before), false);
    expect(FridayAgent.verify(a, view('b', []), before: before), true);
    expect(FridayAgent.verify(a, view('b', [])), false);
  });
  test('scroll requires fresh matching-container directional event not spinner',
      () {
    final before = view('a', [
      {
        'scrollable': true,
        'bounds': [0, 20, 400, 700]
      }
    ]);
    final a =
        AgentAction(action: 'scroll', text: 'down', expect: {'package': pkg});
    final after = view('b', [])
      ..['scrollEvent'] = {
        'revision': 2,
        'package': pkg,
        'bounds': [0, 20, 400, 700],
        'moved': true,
        'direction': 'down'
      };
    expect(FridayAgent.verify(a, view('spinner', []), before: before), false);
    expect(FridayAgent.verify(a, after, before: before), true);
    expect(
        FridayAgent.verify(a, after,
            before: {...before, 'scrollEvent': after['scrollEvent']}),
        false);
    (after['scrollEvent'] as Map)['direction'] = 'up';
    expect(FridayAgent.verify(a, after, before: before), false);
    (after['scrollEvent'] as Map)['direction'] = 'down';
    (after['scrollEvent'] as Map)['bounds'] = [1, 2, 3, 4];
    expect(FridayAgent.verify(a, after, before: before), false);
  });
  test('type verifies the intended exact unique field', () {
    final a = AgentAction(
        action: 'type',
        target: {'resourceId': 'search'},
        text: 'cats',
        expect: {'package': pkg, 'textEquals': 'cats'});
    expect(
        FridayAgent.verify(
            a,
            view('b', [
              {'editable': true, 'resourceId': 'other', 'text': 'cats'}
            ])),
        false);
    expect(
        FridayAgent.verify(
            a,
            view('b', [
              {'editable': true, 'resourceId': 'search', 'text': 'cats'}
            ])),
        true);
    expect(
        FridayAgent.verify(
            a,
            view(
                'b',
                List.generate(
                    2,
                    (_) => {
                          'editable': true,
                          'resourceId': 'search',
                          'text': 'cats'
                        }))),
        false);
  });
  test('WhatsApp opener and focus have concrete field postconditions', () {
    const wa = 'com.whatsapp';
    final goal = AgentGoal.parse('Open WhatsApp and open chat with Alice')!;
    final opener = WorkflowPlanner.next(goal, {
      'package': wa,
      'elements': [
        {'text': 'Search', 'clickable': true}
      ]
    })!;
    expect(opener.expect['searchFieldFocused'], true);
    final field = WorkflowPlanner.next(goal, {
      'package': wa,
      'elements': [
        {'text': '', 'resourceId': 'search', 'editable': true, 'focused': false}
      ]
    })!;
    expect(field.expect['editable'], true);
    expect(field.expect['focused'], true);
    expect(
        FridayAgent.verify(opener, {
          'package': wa,
          'elements': [
            {'resourceId': 'search', 'editable': true, 'focused': true}
          ]
        }),
        true);
  });
  test('delayed command result is observed without a second tap', () async {
    final d = SettleDevice(
        view('a', [
          {'text': 'Search'}
        ]),
        [
          view('a', [
            {'text': 'Search'}
          ])
            ..['settlingTimedOut'] = true,
          view('b', [
            {'editable': true}
          ])
        ]);
    final agent = FridayAgent(brain: NoBrain(), device: d);
    await agent.start('tap Search');
    expect(d.acts, 1);
    expect(d.waits, 2);
    expect(agent.commandIndex, 1);
  });
  test('unverified dispatched command stops rather than repeating side effect',
      () async {
    final d = SettleDevice(
        view('a', [
          {'text': 'Search'}
        ]),
        [
          view('a', [
            {'text': 'Search'}
          ])
        ]);
    final agent = FridayAgent(brain: NoBrain(), device: d);
    await agent.start('tap Search');
    expect(d.acts, 1);
    expect(agent.commandIndex, 0);
    expect(agent.result, contains('not repeated'));
  });
  test('Stop during settling cannot advance command', () async {
    final d = SettleDevice(
        view('a', [
          {'text': 'Search'}
        ]),
        [
          view('a', [
            {'text': 'Search'}
          ])
        ]);
    final agent = FridayAgent(brain: NoBrain(), device: d);
    final work = agent.start('tap Search');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    agent.stop();
    await work;
    expect(agent.commandIndex, 0);
    expect(agent.result, 'Stopped');
    expect(d.acts, 1);
  });
  test('duplicate fields, popups and sensitive targets stay fail-closed', () {
    final g = AgentGoal.parse('Open YouTube and search for cats')!;
    final duplicated = {
      'package': pkg,
      'elements': [
        {'resourceId': 'search_box', 'editable': true},
        {'resourceId': 'search_box', 'editable': true}
      ]
    };
    expect(WorkflowPlanner.next(g, duplicated), isNull);
    expect(
        WorkflowPlanner.next(g, {
          'package': pkg,
          'elements': [
            {'text': 'Allow permission', 'clickable': true}
          ]
        }),
        isNull);
    for (final text in ['Send', 'Delete', 'Buy', 'Allow', 'Login']) {
      expect(
          g.permits(AgentAction(action: 'tap', target: {'text': text})), false);
    }
  });
}
