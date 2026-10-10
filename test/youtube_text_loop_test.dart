import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:friday/services/agent/agent_contract.dart';
import 'package:friday/services/agent/workflow_planner.dart';
import 'package:friday/services/agent/friday_agent.dart';

const pkg = 'com.google.android.youtube';
Map<String, dynamic> searchView(String text) => {
      'success': true,
      'package': pkg,
      'token': 'editing-$text',
      'elements': [
        {
          'resourceId': 'com.google.android.youtube:id/search_edit_text',
          'text': text,
          'editable': true,
          'focused': true
        },
        {
          'resourceId': 'com.google.android.youtube:id/search_clear_button',
          'contentDescription': 'Clear search query',
          'clickable': true,
          'editable': false
        },
        {
          'resourceId': 'com.google.android.youtube:id/suggestion',
          'text': 'GTA 6',
          'editable': false,
          'clickable': true
        },
      ]
    };
Map<String, dynamic> resultView() => {
      'success': true,
      'package': pkg,
      'token': 'results',
      'elements': [
        {
          'resourceId': 'com.google.android.youtube:id/search_edit_text',
          'text': 'GTA 6',
          'editable': true,
          'focused': false
        },
        {
          'resourceId': 'com.google.android.youtube:id/video_title',
          'text': 'GTA 6 official trailer',
          'editable': false
        },
        {'text': 'Filters', 'editable': false},
        {'text': 'Videos', 'editable': false}
      ]
    };

class RecipeBrain implements AgentBrain {
  @override
  Future<AgentAction> decide(
          AgentGoal g, Map<String, dynamic> s, List<String> h) async =>
      WorkflowPlanner.next(g, s, h) ??
      AgentAction(action: 'ask_confirmation', confidence: 1);
}

class ReplayDevice implements AgentDevice {
  String text = '';
  bool results = false;
  int writes = 0, submits = 0, clearTaps = 0;
  final bool eraseAfterWrite;
  ReplayDevice({this.eraseAfterWrite = false});
  @override
  Future<Map<String, dynamic>> call(String method,
      [Map<String, dynamic> args = const {}]) async {
    if (method == 'observe') return results ? resultView() : searchView(text);
    if (method == 'act') {
      final a = args['action'] as Map;
      if (a['action'] == 'type') {
        writes++;
        text = a['text'] as String;
      }
      if (a['action'] == 'submit') {
        submits++;
        if (eraseAfterWrite) {
          text = '';
        } else {
          results = true;
        }
      }
      if (a['action'] == 'tap' &&
          (a['target'] as Map)['resourceId']?.toString().contains('clear') ==
              true) {
        clearTaps++;
        text = '';
      }
      return {'success': true};
    }
    return {'success': true};
  }
}

void main() {
  final g = AgentGoal.parse('Open YouTube and search for GTA 6')!;
  test('autocomplete plus clear button never suppresses exact-field submit',
      () {
    final view = searchView('GTA 6');
    final a = WorkflowPlanner.next(g, view)!;
    expect(a.action, 'submit');
    expect(a.target['resourceId'], '$pkg:id/search_edit_text');
    expect(FridayAgent.complete(g, view), false);
    expect(FridayAgent.verify(a, view), false);
    expect(FridayAgent.verify(a, resultView()), true);
    expect(FridayAgent.complete(g, resultView()), true);
  });
  test('clear controls rejected by planner, goal gate and native gate', () {
    final view = {
      'package': pkg,
      'elements': [
        {
          'resourceId': 'search_clear_button',
          'contentDescription': 'Clear search query',
          'clickable': true
        }
      ]
    };
    expect(WorkflowPlanner.next(g, view), isNull);
    expect(
        g.permits(AgentAction(
            action: 'tap',
            target: {'resourceId': 'search_clear_button'},
            confidence: 1)),
        false);
    final native = File(
            'android/app/src/main/kotlin/com/friday/assistant/FridayAccessibilityService.kt')
        .readAsStringSync();
    expect(native, contains('Clear or dismiss is not a search-opening action'));
    expect(native, contains('ACTION_SET_TEXT'));
    expect(native, contains('ACTION_IME_ENTER'));
  });
  test('verified text loss pauses instead of another write', () {
    final a =
        WorkflowPlanner.next(g, searchView(''), ['Step 1 type: verified'])!;
    expect(a.action, 'ask_confirmation');
    expect(a.reason, contains('disappeared'));
  });
  test('full replay writes once submits once never clears and verifies results',
      () async {
    final d = ReplayDevice();
    final a = FridayAgent(brain: RecipeBrain(), device: d);
    await a.start(g.task);
    expect(a.result, 'Done');
    expect(d.writes, 1);
    expect(d.submits, 1);
    expect(d.clearTaps, 0);
  });
  test('query disappears after submit replay stops without blind retype',
      () async {
    final d = ReplayDevice(eraseAfterWrite: true);
    final a = FridayAgent(brain: RecipeBrain(), device: d);
    await a.start(g.task);
    expect(a.result, isNot('Done'));
    expect(d.writes, 1);
    expect(d.submits, 1);
    expect(d.clearTaps, 0);
  });
}
