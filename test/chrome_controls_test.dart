import 'package:flutter_test/flutter_test.dart';
import 'package:friday/services/agent/chrome_controls.dart';
import 'package:friday/services/agent/workflow_planner.dart';
import 'package:friday/services/agent/agent_contract.dart';
import 'agent_task_routes_test.dart' show n, s;

void main() {
  final g = AgentGoal.parse("Open Chrome and search for today's gold price")!;
  const p = 'com.android.chrome';
  test('canonical address_bar with Address bar label is safely recognized', () {
    final field =
        n('Address bar', '$p:id/address_bar', edit: true, focus: true);
    final a = WorkflowPlanner.next(
        g, s(p, [field, n('Search or type URL', 'search_box')]));
    expect(a?.action, 'type');
    expect(a?.target['resourceId'], '$p:id/address_bar');
    expect(a?.text, g.query);
  });
  test('unrecognized sole editor does not become search bar', () {
    final es = [n('Email', 'email', edit: true, focus: true)];
    expect(ChromeControls.candidates(es), isEmpty);
    expect(ChromeControls.failure(es), 'chrome_unrecognized_editor');
    expect(WorkflowPlanner.next(g, s(p, es)), isNull);
  });
  test('canonical address bar does not override a second editor', () {
    final es = [
      n('', '$p:id/url_bar', edit: true),
      n('Password', 'password', edit: true)
    ];
    expect(ChromeControls.candidates(es), isEmpty);
    expect(ChromeControls.failure(es), 'chrome_multiple_editors');
  });
  test('foreign package resource ID cannot claim canonical authority', () {
    expect(
        ChromeControls.canonical(n('', 'attacker:id/address_bar', edit: true)),
        false);
  });
  test('containers clear and mic controls never replace canonical editor', () {
    final es = [
      n('Search or type URL', 'search_box'),
      n('Clear', 'clear'),
      n('Voice search', 'voice_search'),
      n('', '$p:id/url_bar', edit: true, focus: true)
    ];
    expect(ChromeControls.candidates(es).single['resourceId'], '$p:id/url_bar');
  });
  test('multiple containers get distinct ambiguity code', () {
    expect(
        ChromeControls.failure(
            [n('Search', 'search_box'), n('Search or type URL', 'omnibox')]),
        'chrome_ambiguous_navigation');
  });
}
