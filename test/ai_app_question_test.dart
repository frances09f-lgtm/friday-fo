import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:friday/services/agent/agent_contract.dart';
import 'package:friday/services/agent/workflow_planner.dart';
import 'package:friday/services/device/device_hub.dart';
import 'agent_task_routes_test.dart' show n, s;

void main() {
  test('named assistant queries deterministic, exact query retained', () {
    for (final app in ['Deep sick', 'DeepSeek', 'deep seek', 'Gemini']) {
      final g = AgentGoal.parse('search for GTA 6 release date on $app')!;
      expect(g.query, 'GTA 6 release date');
      expect(g.workflow, 'question');
      expect(g.noPlanner, true);
      expect(
          g.package,
          app == 'Gemini'
              ? 'com.google.android.apps.bard'
              : 'com.deepseek.chat');
      expect(AgentGoal.parse('ask $app who won the match')!.query,
          'who won the match');
    }
  });
  test('package alias never falls through to lookalike', () {
    final official = InstalledApp(
        label: 'DeepSeek - AI Assistant', packageName: 'com.deepseek.chat');
    final fake = InstalledApp(label: 'Deep sick', packageName: 'other');
    expect(DeviceHub.matchApp('deep sick', [fake]), isNull);
    expect(DeviceHub.matchApp('deep sick', [fake, official]), official);
    expect(
        DeviceHub.matchApp(
            'Gemini', [InstalledApp(label: 'Gemini', packageName: 'other')]),
        isNull);
  });
  test('one observed empty composer only, no overwritten draft or wrong app',
      () {
    final g = AgentGoal.parse('ask Gemini test question')!;
    expect(
        WorkflowPlanner.next(
                g, s(g.package, [n('', 'prompt', edit: true, focus: true)]))
            ?.action,
        'type');
    expect(
        WorkflowPlanner.next(
            g,
            s(g.package,
                [n('My unsent draft', 'prompt', edit: true, focus: true)])),
        isNull);
    expect(
        WorkflowPlanner.next(
            g,
            s(g.package,
                [n('', 'prompt', edit: true), n('', 'other', edit: true)])),
        isNull);
    expect(
        g.permits(AgentAction(
            action: 'open_app', target: {'package': 'com.android.chrome'})),
        false);
    expect(
        g.permits(AgentAction(
            action: 'search_intent',
            target: {'package': g.package},
            text: g.query)),
        false);
  });
  test('native independent checks keep exact package query and visible submit',
      () {
    final native = File(
            'android/app/src/main/kotlin/com/friday/assistant/FridayAccessibilityService.kt')
        .readAsStringSync();
    expect(native, contains('allowed in questionApps'));
    expect(native, contains('Existing draft needs user review'));
    expect(native,
        contains('nodes.count{it.isEditable&&it.text?.toString()==query}==1'));
  });
}
