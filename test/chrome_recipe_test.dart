import 'package:flutter_test/flutter_test.dart';
import 'package:friday/services/agent/agent_contract.dart';
import 'package:friday/services/agent/friday_agent.dart';
import 'package:friday/services/agent/workflow_planner.dart';

class ChromeIntentDevice implements AgentDevice {
  int intents = 0;
  bool results = false;
  final bool noop;
  ChromeIntentDevice({this.noop = false});
  @override
  Future<Map<String, dynamic>> call(String method,
      [Map<String, dynamic> args = const {}]) async {
    if (method == 'act' &&
        (args['action'] as Map)['action'] == 'search_intent') {
      intents++;
      results = !noop;
    }
    if (method == 'observe')
      return {
        'success': true,
        'package': 'com.android.chrome',
        'token': results ? 'results' : 'idle',
        'elements': <Map<String, dynamic>>[
          {
            'resourceId': 'url_bar',
            'text': results
                ? 'https://www.google.com/search?q=latest+gold+price'
                : 'idle',
            'editable': false
          }
        ]
      };
    return {'success': true};
  }
}

class ChromeRetryBrain implements AgentBrain {
  @override
  Future<AgentAction> decide(
          AgentGoal g, Map<String, dynamic> s, List<String> h) async =>
      AgentAction(
          action: 'tap',
          target: {'resourceId': 'url_bar'},
          confidence: 1,
          expect: {'package': g.package, 'editable': true, 'focused': true});
}

void main() {
  final g = AgentGoal.parse('Open Chrome and search for latest gold price')!;
  Map<String, dynamic> s(List<Map<String, dynamic>> e) =>
      {'package': g.package, 'elements': e};
  test('two failed UI actions use one verified results fallback', () async {
    final d = ChromeIntentDevice();
    final a = FridayAgent(brain: ChromeRetryBrain(), device: d);
    await a.start(g.task);
    expect(a.result, 'Done');
    expect(d.intents, 1);
  });
  test('Chrome intent no-op is not completion', () async {
    final d = ChromeIntentDevice(noop: true);
    final a = FridayAgent(brain: ChromeRetryBrain(), device: d);
    await a.start(g.task);
    expect(a.result, isNot('Done'));
    expect(d.intents, 1);
  });
  test('Chrome focuses observed omnibox before typing and submits exact query',
      () {
    final idle = {
      'resourceId': 'com.android.chrome:id/url_bar',
      'text': 'Search or type web address',
      'editable': false,
      'clickable':
          true, // Android capture explicitly reports actionable NTP bars.
      'focused': false
    };
    final tap = WorkflowPlanner.next(g, s([idle]))!;
    expect(tap.action, 'tap');
    expect(g.permits(tap), true);
    final active = {...idle, 'editable': true, 'focused': true};
    expect(FridayAgent.verify(tap, s([active])), true);
    final type = WorkflowPlanner.next(g, s([active]))!;
    expect(type.action, 'type');
    expect(type.text, g.query);
    final typed = {...active, 'text': g.query};
    expect(WorkflowPlanner.next(g, s([typed]))!.action, 'submit');
    expect(FridayAgent.complete(g, s([typed])), false);
  });
  test('Chrome result verification uses exact observed search URL query', () {
    final result = s([
      {
        'resourceId': 'com.android.chrome:id/url_bar',
        'text': 'https://www.google.com/search?q=latest+gold+price'
      }
    ]);
    expect(FridayAgent.complete(g, result), true);
    expect(
        FridayAgent.complete(
            g,
            s([
              {
                'resourceId': 'com.android.chrome:id/url_bar',
                'text': 'https://www.google.com/search?q=wrong'
              }
            ])),
        false);
  });
  test('ambiguous omnibox recipe refuses and wrong app cannot complete', () {
    expect(
        WorkflowPlanner.next(
            g,
            s([
              {'resourceId': 'url_bar'},
              {'resourceId': 'url_bar'}
            ])),
        isNull);
    expect(
        FridayAgent.complete(g, {
          'package': 'other',
          'elements': [
            {
              'resourceId': 'url_bar',
              'text': 'https://google.com/search?q=latest+gold+price'
            }
          ]
        }),
        false);
  });
}
