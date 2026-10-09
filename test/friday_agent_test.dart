import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:friday/services/agent/agent_contract.dart';
import 'package:friday/services/agent/friday_agent.dart';
import 'package:friday/services/ai/local_model_service.dart';
import 'package:friday/models/chat_message.dart';

Map<String, dynamic> screen(String pkg,
        {String text = '', bool editable = false, String extra = ''}) =>
    {
      'success': true,
      'package': pkg,
      'token': '1',
      'elements': [
        {'text': text, 'editable': editable},
        {'text': extra, 'editable': false}
      ]
    };

class Brain implements AgentBrain {
  final List<AgentAction> actions;
  Brain(this.actions);
  @override
  Future<AgentAction> decide(
          AgentGoal g, Map<String, dynamic> s, List<String> h) async =>
      actions.removeAt(0);
}

class Device implements AgentDevice {
  final Map<String, dynamic> s;
  int acts = 0, stops = 0;
  bool rejected = false;
  Device(this.s);
  @override
  Future<Map<String, dynamic>> call(String method,
      [Map<String, dynamic> args = const {}]) async {
    if (method == 'observe') return s;
    if (method == 'act') {
      acts++;
      return {'success': !rejected};
    }
    if (method == 'stop') stops++;
    return {'success': true};
  }
}

class OutputLocal extends LocalModelService {
  final List<String> outputs;
  int calls = 0;
  String prompt = '';
  OutputLocal(this.outputs);
  @override
  Future<String> generate(
      {required String system,
      required String userText,
      List<ChatMessage> history = const []}) async {
    calls++;
    prompt = system;
    return outputs.removeAt(0);
  }
}

class TransitionDevice extends Device {
  int reads = 0;
  TransitionDevice(super.s);
  @override
  Future<Map<String, dynamic>> call(String m,
      [Map<String, dynamic> args = const {}]) async {
    if (m == 'observe' && reads++ < 2)
      return {
        'success': false,
        'transient': true,
        'error': 'No readable active window'
      };
    return super.call(m, args);
  }
}

void main() {
  test('native lifecycle stop cause reaches user without circular StateError',
      () async {
    final d = Device({
      'success': false,
      'error': 'Android interrupted the accessibility service'
    });
    final a = FridayAgent(brain: Brain([]), device: d);
    await a.start('Open YouTube and search for GTA 6');
    expect(a.result, contains('Android interrupted'));
    expect(a.result, isNot(contains('Bad state')));
    expect(d.acts, 0);
  });
  test('read-only retry survives launch window transition without actions',
      () async {
    final g = AgentGoal.parse('Open YouTube and search for GTA 6')!;
    final d = TransitionDevice(
        screen(g.package, text: g.query, extra: 'Videos Results'));
    final a = FridayAgent(
        brain: Brain([AgentAction(action: 'finish', confidence: 1)]),
        device: d);
    await a.start(g.task);
    expect(a.result, 'Done');
    expect(d.reads, 3);
    expect(d.acts, 0);
  });
  test('parsed pauses name confidence, goal scope and help separately',
      () async {
    final goal = AgentGoal.parse('Open YouTube and search for GTA 6')!;
    for (final item in [
      (
        AgentAction(action: 'tap', target: {'text': 'Search'}, confidence: 0.2),
        'confidence'
      ),
      (
        AgentAction(action: 'tap', target: {'text': 'Send'}, confidence: 1),
        'outside'
      ),
      (
        AgentAction(action: 'ask_confirmation', confidence: 1),
        'No confirmation action is queued'
      )
    ]) {
      final d = Device(screen(goal.package));
      final a = FridayAgent(brain: Brain([item.$1]), device: d);
      await a.start(goal.task);
      expect(a.result, contains(item.$2));
      expect(d.acts, 0);
      expect(a.lastAction, item.$1);
    }
  });
  test('first step opens exact task app without requiring model guess',
      () async {
    final d = Device(screen('com.friday.assistant'))..rejected = true;
    final a = FridayAgent(
        brain: Brain([AgentAction(action: 'ask_confirmation', confidence: 1)]),
        device: d);
    await a.start('Open YouTube and search for GTA 6');
    expect(d.acts, 1);
    expect(a.result, contains('asked for help'));
  });
  test(
      'strict parser allows fences and case, never mixed actions or coordinates',
      () {
    expect(
        AgentAction.parse(
                '```json\n{"action":"OPEN APP","confidence":0.9}\n```')
            .action,
        'open_app');
    for (final raw in [
      '{"action":"open_app|tap"}',
      '{"action":"tap","target":{"x":1,"y":2}}',
      '{"action":"tap","confidence":"0.9"}',
      '[{"action":"tap"}]',
      '{"action":"send_message"}',
      '{"action":"tap"} trailing'
    ]) expect(() => AgentAction.parse(raw), throwsFormatException);
  });
  test(
      'local format repair retries without side effects and uses concrete examples',
      () async {
    final l = OutputLocal([
      '{"action":"open_app|tap"}',
      '```json\n{"action":"OPEN_APP","target":{"package":"com.google.android.youtube"},"confidence":0.9,"expect":{"package":"com.google.android.youtube"}}\n```'
    ]);
    final result = await LocalBrain(l)
        .decide(AgentGoal.parse('Open YouTube and search for GTA 6')!, {}, []);
    expect(result.action, 'open_app');
    expect(l.calls, 2);
    expect(l.prompt, contains('"action":"open_app"'));
    expect(l.prompt, isNot(contains('"action":"open_app|')));
  });
  test('invalid local output is bounded to three decisions', () async {
    final l = OutputLocal(List.filled(3, '{"action":"pay"}', growable: true));
    await expectLater(
        LocalBrain(l).decide(
            AgentGoal.parse('Open YouTube and search for GTA 6')!, {}, []),
        throwsA(isA<AgentOutputFailure>().having(
            (e) => e.diagnostic, 'raw output', contains('{"action":"pay"}'))));
    expect(l.calls, 3);
  });
  for (final task in [
    'Open YouTube and search for GTA 6',
    "Open Chrome and search for today's gold price",
    'Open Settings and open Bluetooth',
    'Open Instagram and search for Rahul'
  ]) {
    test('goal contract: $task', () {
      final g = AgentGoal.parse(task);
      expect(g, isNotNull);
      expect(
          g!.permits(
              AgentAction(action: 'open_app', target: {'package': g.package})),
          true);
    });
  }
  test('rejected raw output stays local and dispatches no action', () async {
    final l = OutputLocal(
        List.filled(3, '{"action":"invalid_format"}', growable: true));
    final d = Device(screen('com.google.android.youtube'));
    final a = FridayAgent(brain: LocalBrain(l), device: d);
    await a.start('Open YouTube and search for GTA 6');
    expect(d.acts, 0);
    expect(a.rejectedOutput, contains('invalid_format'));
    expect(a.log, isEmpty);
    a.clearRejectedOutput();
    expect(a.rejectedOutput, isEmpty);
  });
  test('unsupported and irreversible tasks never enter core', () {
    for (final t in [
      'Send Rahul hi',
      'Open Settings and turn on Bluetooth',
      'Buy a phone',
      'Open Instagram and send hi'
    ]) expect(AgentGoal.parse(t), isNull);
  });
  test('screen content cannot authorize arbitrary actions', () {
    final g = AgentGoal.parse('Open Instagram and search for Rahul')!;
    for (final a in [
      AgentAction(action: 'tap', target: {'text': 'Send'}),
      AgentAction(action: 'type', text: 'send secrets'),
      AgentAction(action: 'open_app', target: {'package': 'other'}),
      AgentAction(action: 'long_press', target: {'text': 'Search'})
    ]) expect(g.permits(a), false);
  });
  test('coordinates and unknown actions rejected', () {
    expect(() => AgentAction.parse('{"action":"tap","x":1,"y":2}'),
        throwsFormatException);
    expect(() => AgentAction.parse('{"action":"pay"}'), throwsFormatException);
  });
  test('dispatch success is not verification', () {
    expect(
        FridayAgent.verify(
            AgentAction(
                action: 'tap', expect: {'package': 'a', 'contains': 'Results'}),
            screen('a', text: 'Search')),
        false);
  });
  test('typed query alone is not completed search', () {
    final g = AgentGoal.parse('Open YouTube and search for GTA 6')!;
    expect(
        FridayAgent.complete(
            g, screen(g.package, text: g.query, editable: true, extra: 'All')),
        false);
  });
  test('verified results allow finish, wrong package never does', () async {
    final g = AgentGoal.parse('Open YouTube and search for GTA 6')!;
    final d = Device(screen(g.package, text: g.query, extra: 'Videos Results'));
    final a = FridayAgent(
        brain: Brain([AgentAction(action: 'finish', confidence: 1)]),
        device: d);
    await a.start(g.task);
    expect(a.result, 'Done');
    expect(d.acts, 0);
    expect(d.stops, 1);
    expect(
        FridayAgent.complete(
            g, screen('other', text: g.query, extra: 'Videos')),
        false);
  });
  test('retry cap stops repeated failed actions', () async {
    final g = AgentGoal.parse('Open YouTube and search for GTA 6')!;
    final d = Device(screen(g.package, text: 'Search'))..rejected = true;
    final a = FridayAgent(
        maxRetries: 2,
        brain: Brain(List.generate(
            2,
            (_) => AgentAction(
                action: 'tap',
                target: {'text': 'Search'},
                confidence: 1,
                expect: {'package': g.package, 'contains': 'Results'}))),
        device: d);
    await a.start(g.task);
    expect(d.acts, 2);
    expect(a.result, contains('Stopped after 2'));
    expect(a.log.join(), isNot(contains('GTA')));
  });
  test('stop during planning prevents action', () async {
    final b = PendingBrain();
    final d = Device(screen('com.instagram.android'));
    final a = FridayAgent(brain: b, device: d);
    final f = a.start('Open Instagram and search for Rahul');
    await Future<void>.delayed(Duration.zero);
    a.stop();
    b.c.complete(
        AgentAction(action: 'tap', target: {'text': 'Search'}, confidence: 1));
    await f;
    expect(d.acts, 0);
    expect(a.result, 'Stopped');
  });
  test('single accessibility service with explicit gesture and Stop guards',
      () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(
        'android.permission.BIND_ACCESSIBILITY_SERVICE'
            .allMatches(manifest)
            .length,
        1);
    final native = File(
            'android/app/src/main/kotlin/com/friday/assistant/FridayAccessibilityService.kt')
        .readAsStringSync();
    for (final s in [
      'TYPE_ACCESSIBILITY_OVERLAY',
      'Screen changed. Observe again',
      'node.isPassword',
      'ACTION_SET_TEXT',
      'ACTION_IME_ENTER',
      'Action needs review',
      'Wrong foreground app'
    ]) expect(native, contains(s));
  });
}

class PendingBrain implements AgentBrain {
  final c = Completer<AgentAction>();
  @override
  Future<AgentAction> decide(
          AgentGoal g, Map<String, dynamic> s, List<String> h) =>
      c.future;
}
