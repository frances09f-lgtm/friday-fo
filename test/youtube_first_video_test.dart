import 'package:flutter_test/flutter_test.dart';
import 'package:friday/services/agent/agent_contract.dart';
import 'package:friday/services/agent/workflow_planner.dart';

void main() {
  test('compound phrase preserves query and play-first intent', () {
    final g =
        AgentGoal.parse('open youtube search for gta6 and play first video')!;
    expect(g.query, 'gta6');
    expect(g.workflow, 'play');
    expect(g.firstVideo, true);
    expect(g.withPackage(g.package).firstVideo, true);
  });
  test('first regular observed relevant video excludes ad/shorts/navigation',
      () {
    final g =
        AgentGoal.parse('open youtube search for gta6 and play first video')!;
    final s = {
      'package': g.package,
      'elements': <Map<String, dynamic>>[
        {'text': 'gta6 Videos Results'},
        {
          'text': 'gta6 sponsored',
          'resourceId': 'video_title',
          'clickable': true
        },
        {'text': 'gta6 Shorts', 'resourceId': 'video_title', 'clickable': true},
        {
          'text': 'gta6 official trailer',
          'resourceId': 'video_title',
          'bounds': [0, 100, 500, 200],
          'clickable': true
        },
        {
          'text': 'gta6 review',
          'resourceId': 'video_title',
          'bounds': [0, 300, 500, 400],
          'clickable': true
        }
      ]
    };
    expect(WorkflowPlanner.next(g, s)!.target['text'], 'gta6 official trailer');
  });
  test('missing result-card evidence asks instead of random tap', () {
    final g =
        AgentGoal.parse('open youtube search for gta6 and play first video')!;
    expect(
        WorkflowPlanner.next(g, {
          'package': g.package,
          'elements': [
            {'text': 'gta6 Videos Results'},
            {'text': 'gta6', 'clickable': true}
          ]
        })!
            .action,
        'ask_confirmation');
  });
}
