import 'package:flutter_test/flutter_test.dart';
import 'package:friday/services/agent/gallery_command.dart';
import 'package:friday/services/agent/agent_contract.dart';
import 'package:friday/services/agent/friday_agent.dart';
import 'package:friday/services/agent/workflow_planner.dart';

void main() {
  test('Gallery bounded ordinal explicit source', () {
    expect(GalleryCommand.parse('open gallery and play first video'), 1);
    expect(GalleryCommand.parse('open gallery and play 50th video'), 50);
    expect(GalleryCommand.parse('open gallery and play 51st video'), null);
    expect(GalleryCommand.parse('play first video'), null);
    expect(GalleryCommand.parse('open gallery and play second video'), 2);
  });
  test('WhatsApp search exact field and observed results, no chat opening', () {
    final g = AgentGoal.parse('open WhatsApp and search for Mayuri')!;
    expect(g.workflow, 'search');
    expect(g.package, 'com.whatsapp');
    final s = {
      'package': g.package,
      'elements': [
        {
          'editable': true,
          'focused': true,
          'resourceId': 'search_src_text',
          'text': 'Mayuri',
          'bounds': [0, 0, 100, 50]
        },
        {'text': 'Mayuri', 'clickable': true}
      ]
    };
    expect(FridayAgent.complete(g, s), true);
    expect(WorkflowPlanner.next(g, s)!.action, 'wait');
    expect(
        g.permits(AgentAction(
            action: 'tap', target: {'text': 'Mayuri'}, confidence: 1)),
        false);
  });
  test('selector carries observed bounds not invented coordinates', () {
    final g = AgentGoal.parse('open youtube and search for cars')!;
    final a = WorkflowPlanner.next(g, {
      'package': g.package,
      'elements': [
        {
          'text': 'Search',
          'clickable': true,
          'bounds': [10, 20, 50, 60]
        }
      ]
    })!;
    expect(a.target['bounds'], [10, 20, 50, 60]);
  });
}
