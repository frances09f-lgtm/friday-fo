import 'package:flutter_test/flutter_test.dart';
import 'package:friday/services/agent/agent_contract.dart';
import 'package:friday/services/agent/workflow_planner.dart';

void main() {
  test(
      'YouTube exact typed query submits IME then different unique Search button',
      () {
    final g = AgentGoal.parse('Open YouTube and search for GTA 6')!;
    final screen = {
      'package': g.package,
      'elements': [
        {'resourceId': 'search_edit_text', 'text': 'GTA 6', 'editable': true},
        {'contentDescription': 'Search', 'clickable': true, 'editable': false}
      ]
    };
    final ime = WorkflowPlanner.next(g, screen)!;
    expect(ime.action, 'submit');
    expect(ime.target['resourceId'], 'search_edit_text');
    expect(ime.text, g.query);
    final button =
        WorkflowPlanner.next(g, screen, ['Step 2 submit: not verified'])!;
    expect(button.action, 'submit');
    expect(button.target['contentDescription'], 'Search');
    expect(button.text, g.query);
    expect(g.permits(button), true);
  });
  test('duplicate Search buttons never used as alternate submit', () {
    final g = AgentGoal.parse('Open YouTube and search for GTA 6')!;
    final screen = {
      'package': g.package,
      'elements': [
        {'resourceId': 'search_edit_text', 'text': 'GTA 6', 'editable': true},
        {'contentDescription': 'Search', 'clickable': true},
        {'contentDescription': 'Search', 'clickable': true}
      ]
    };
    expect(
        WorkflowPlanner.next(g, screen, ['submit: not verified'])!
            .target['resourceId'],
        'search_edit_text');
  });
}
