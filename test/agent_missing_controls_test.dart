import 'package:flutter_test/flutter_test.dart';
import 'package:friday/services/agent/agent_contract.dart';
import 'package:friday/services/agent/friday_agent.dart';
import 'package:friday/services/agent/workflow_planner.dart';
import 'agent_task_routes_test.dart' show NoModel, n, s, route;

void main() {
  const chrome = 'com.android.chrome';
  final goal =
      AgentGoal.parse("Open Chrome and search for today's gold price")!;
  test('Chrome NTP container does not obscure unique real editable omnibox',
      () {
    final screen = s(chrome, [
      n('Search or type URL', 'search_box'),
      n('', 'com.android.chrome:id/url_bar', edit: true, focus: true)
    ]);
    final a = WorkflowPlanner.next(goal, screen);
    expect(a?.action, 'type');
    expect(a?.target['resourceId'], 'com.android.chrome:id/url_bar');
  });
  test('Chrome known field not confused by clear omnibox button', () {
    final a = WorkflowPlanner.next(
        goal,
        s(chrome, [
          n('', 'com.android.chrome:id/url_bar', edit: true, focus: true),
          n('Clear', 'omnibox_clear_button')
        ]));
    expect(a?.action, 'type');
  });
  test(
      'bounded missing controls reach exact platform search without action-failure retries',
      () async {
    final model = NoModel();
    final a = await LocalBrain(model).decide(goal, s(chrome, []),
        ['Step 2 wait: verified', 'Step 1 wait: verified']);
    expect(a.action, 'search_intent');
    expect(a.text, goal.query);
    expect(model.calls, 0);
  });
  test(
      'missing-control platform route is verified against results, never launch alone',
      () async {
    await route("Open Chrome and search cats", chrome, [
      [],
      [],
      [],
      [n('https://www.google.com/search?q=cats', 'url_bar')]
    ], [
      'wait',
      'wait',
      'search_intent'
    ]);
  });
  test('ambiguous editors remain stopped', () async {
    final screen = s(chrome, [
      n('', 'url_bar', edit: true, focus: true),
      n('', 'search_box', edit: true, focus: true)
    ]);
    expect(WorkflowPlanner.next(goal, screen), isNull);
    final a = await LocalBrain(NoModel()).decide(
        goal, screen, ['Step 1 wait: verified', 'Step 2 wait: verified']);
    expect(a.action, 'ask_confirmation');
  });
  test(
      'protection and incomplete capture cannot invoke missing-control fallback',
      () async {
    for (final screen in [
      s(chrome, [n('Sign in', 'signin')]),
      s(chrome, [])..['truncated'] = true,
      s(chrome, [])..['blocked'] = true
    ]) {
      final a = await LocalBrain(NoModel()).decide(
          goal, screen, ['Step 1 wait: verified', 'Step 2 wait: verified']);
      expect(a.action, 'ask_confirmation');
    }
  });
  test('Chrome typed search URL while editing is not completed', () {
    expect(
        FridayAgent.complete(
            goal,
            s(chrome, [
              n('https://www.google.com/search?q=today%27s+gold+price',
                  'url_bar',
                  edit: true, focus: true)
            ])),
        false);
  });
}
