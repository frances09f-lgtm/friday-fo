import 'package:flutter_test/flutter_test.dart';
import 'package:friday/services/agent/agent_contract.dart';
import 'package:friday/services/agent/friday_agent.dart';
import 'package:friday/services/agent/workflow_planner.dart';

Map<String, dynamic> searchField(String text, bool focused) => {
      'success': true,
      'package': 'com.google.android.youtube',
      'token': '$text-$focused',
      'elements': <Map<String, dynamic>>[
        {
          'text': text,
          'resourceId': 'youtube:id/search_edit_text',
          'editable': true,
          'focused': focused,
          'clickable': true
        }
      ]
    };

class RepeatBrain implements AgentBrain {
  @override
  Future<AgentAction> decide(
      AgentGoal g, Map<String, dynamic> s, List<String> history) async {
    final action = WorkflowPlanner.next(g, s, history);
    if (action == null) throw StateError('Repeat workflow fell through');
    return action;
  }
}

class RepeatDevice implements AgentDevice {
  Map<String, dynamic> current = {
    'success': true,
    'package': 'launcher',
    'token': 'initial',
    'elements': <Map<String, dynamic>>[]
  };
  int starts = 0, stops = 0, changes = 0;
  final actions = <String>[];
  bool eraseAfterWrite = false;
  bool intentNoop = false;
  bool eraseOnNextObserve = false;
  String query = '';
  void results(String value) {
    current = {
      'success': true,
      'package': 'com.google.android.youtube',
      'token': 'results-${++changes}',
      'elements': <Map<String, dynamic>>[
        {'text': value, 'editable': false},
        {
          'text': 'Videos Results',
          'resourceId': 'search_results',
          'editable': false
        },
        {
          'contentDescription': 'Search',
          'resourceId': 'menu_item',
          'clickable': true
        },
        {'resourceId': 'search_video', 'text': 'other video', 'clickable': true}
      ]
    };
  }

  @override
  Future<Map<String, dynamic>> call(String method,
      [Map<String, dynamic> args = const {}]) async {
    if (method == 'start') {
      starts++;
      query = args['query'] as String;
    }
    if (method == 'stop') stops++;
    if (method == 'observe') {
      if (eraseOnNextObserve) {
        current = searchField('', true);
        eraseOnNextObserve = false;
      }
      if (eraseAfterWrite &&
          (current['elements'] as List)
              .any((e) => e['editable'] == true && e['text'] == query))
        eraseOnNextObserve = true;
      return current;
    }
    if (method == 'act') {
      final a = args['action'] as Map;
      actions.add(a['action'] as String);
      if (a['action'] == 'open_app') results('old query');
      if (a['action'] == 'tap') current = searchField('', true);
      if (a['action'] == 'type')
        current = searchField(a['text'] as String, true);
      if (a['action'] == 'submit') results(query);
      if (a['action'] == 'search_intent' && !intentNoop) results(query);
    }
    return {'success': true};
  }
}

void main() {
  final g = AgentGoal.parse('Open YouTube and search for GTA 6')!;
  test('same agent runs twice from retained results with fresh lifecycle',
      () async {
    final d = RepeatDevice();
    final a = FridayAgent(brain: RepeatBrain(), device: d);
    await a.start('Open YouTube and search for GTA 6');
    expect(a.result, 'Done');
    await a.start('Open YouTube and search for Minecraft');
    expect(a.result, 'Done');
    expect(d.starts, 2);
    expect(d.stops, 2);
    expect(d.actions,
        ['open_app', 'tap', 'type', 'submit', 'tap', 'type', 'submit']);
  });
  test('lost verified text uses one results intent without rewriting',
      () async {
    final d = RepeatDevice()..eraseAfterWrite = true;
    final a = FridayAgent(brain: RepeatBrain(), device: d);
    await a.start(g.task);
    expect(a.result, 'Done');
    expect(d.actions.where((x) => x == 'type').length, 1);
    expect(d.actions.where((x) => x == 'search_intent').length, 1);
  });
  test('intent dispatch without actual results never claims done', () async {
    final d = RepeatDevice()
      ..eraseAfterWrite = true
      ..intentNoop = true;
    final a = FridayAgent(brain: RepeatBrain(), device: d);
    await a.start(g.task);
    expect(a.result, isNot('Done'));
    expect(d.actions.where((x) => x == 'type').length, 1);
    expect(d.actions.where((x) => x == 'search_intent').length, 1);
  });
  test('results intent scope is exact supported search query only', () {
    expect(
        g.permits(AgentAction(
            action: 'search_intent',
            text: g.query,
            target: {'package': g.package})),
        true);
    expect(
        g.permits(AgentAction(
            action: 'search_intent',
            text: 'other',
            target: {'package': g.package})),
        false);
    final chrome = AgentGoal.parse('Open Chrome and search for GTA 6')!;
    expect(
        chrome.permits(AgentAction(
            action: 'search_intent',
            text: chrome.query,
            target: {'package': chrome.package})),
        true);
  });
  test('repeat search focuses retained old field before replacing query', () {
    final action = WorkflowPlanner.next(g, searchField('old query', false))!;
    expect(action.action, 'tap');
    expect(action.expect['focused'], true);
    expect(FridayAgent.verify(action, searchField('old query', false)), false);
    expect(FridayAgent.verify(action, searchField('old query', true)), true);
    expect(WorkflowPlanner.next(g, searchField('old query', true))!.action,
        'type');
  });
  test('exact query without focus is focused, not prematurely submitted', () {
    expect(WorkflowPlanner.next(g, searchField(g.query, false))!.action, 'tap');
    expect(
        WorkflowPlanner.next(g, searchField(g.query, true))!.action, 'submit');
  });
  test('focus loss after verified typing does not trigger a retype', () {
    final history = ['Step 1 type: verified'];
    final action =
        WorkflowPlanner.next(g, searchField(g.query, false), history)!;
    expect(action.action, 'tap');
    expect(WorkflowPlanner.next(g, searchField(g.query, true), history)!.action,
        'submit');
  });
  test('repeat results uses actual Search opener despite search containers',
      () {
    final screen = {
      'package': g.package,
      'elements': [
        {
          'resourceId': 'search_results',
          'text': 'old query',
          'editable': false
        },
        {
          'resourceId': 'menu_item',
          'contentDescription': 'Search',
          'clickable': true
        },
        {
          'resourceId': 'search_video',
          'text': 'another video',
          'clickable': true
        }
      ]
    };
    final a = WorkflowPlanner.next(g, screen)!;
    expect(a.action, 'tap');
    expect(a.target['contentDescription'], 'Search');
    expect(a.expect['searchFieldFocused'], true);
    expect(FridayAgent.verify(a, searchField('', true)), true);
    expect(FridayAgent.verify(a, searchField('', false)), false);
  });
  test('ambiguous editable fields do not produce focus or typing action', () {
    final s = searchField('old query', false);
    (s['elements'] as List)
        .add(Map<String, dynamic>.from((s['elements'] as List).first));
    final action = WorkflowPlanner.next(g, s);
    expect(action, null);
  });
}
