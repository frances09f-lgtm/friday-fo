import 'package:flutter_test/flutter_test.dart';
import 'package:friday/models/chat_message.dart';
import 'package:friday/services/ai/local_model_service.dart';
import 'package:friday/services/agent/agent_contract.dart';
import 'package:friday/services/agent/friday_agent.dart';
import 'package:friday/services/agent/workflow_planner.dart';

class NoModel extends LocalModelService {
  int calls = 0;
  @override
  Future<String> generate(
      {required String system,
      required String userText,
      List<ChatMessage> history = const []}) async {
    calls++;
    throw StateError('No model navigation');
  }
}

Map<String, dynamic> n(String text, String id,
        {bool edit = false, bool focus = false, String desc = ''}) =>
    {
      'text': text,
      'resourceId': id,
      'editable': edit,
      'focused': focus,
      'clickable': true,
      'contentDescription': desc,
      'bounds': [0, 100, 300, 150]
    };
Map<String, dynamic> s(String pkg, List<Map<String, dynamic>> es,
        {String token = 'a'}) =>
    {
      'success': true,
      'package': pkg,
      'token': token,
      'elements': es,
      'eventRevision': 1
    };

class RouteDevice implements AgentDevice {
  final List<Map<String, dynamic>> screens;
  final List<String> expected;
  final actions = <Map<String, dynamic>>[];
  int at = 0;
  RouteDevice(this.screens, this.expected);
  @override
  Future<Map<String, dynamic>> call(String method,
      [Map<String, dynamic> args = const {}]) async {
    if (method == 'start')
      return {'success': true, 'package': screens.first['package']};
    if (method == 'observe' || method == 'await_screen') return screens[at];
    if (method == 'act') {
      final a = Map<String, dynamic>.from(args['action']);
      actions.add(a);
      expect(a['action'], expected[at], reason: 'stage $at');
      expect(args['token'], screens[at]['token']);
      if (at < screens.length - 1) at++;
    }
    return {'success': true};
  }
}

Future<void> route(String task, String pkg,
    List<List<Map<String, dynamic>>> stages, List<String> actions,
    {bool audio = false}) async {
  final screens = [
    for (var i = 0; i < stages.length; i++) s(pkg, stages[i], token: '$i')
  ];
  if (audio) screens.last['audioActive'] = true;
  final model = NoModel();
  final d = RouteDevice(screens, actions);
  final agent = FridayAgent(brain: LocalBrain(model), device: d);
  await agent.start(task);
  expect(agent.result, 'Done');
  expect(d.actions.map((a) => a['action']).toList(), actions);
  expect(model.calls, 0);
}

void main() {
  const wa = 'com.whatsapp',
      yt = 'com.google.android.youtube',
      chrome = 'com.android.chrome',
      ig = 'com.instagram.android',
      gpt = 'com.openai.chatgpt',
      settings = 'com.android.settings';
  test('all seven displayed examples parse to intended route', () {
    final tasks = {
      'Open YouTube and play GTA 6': 'play',
      'Open WhatsApp and open my chat with Rahul': 'contact',
      'Open ChatGPT and search for explain gravity': 'question',
      'Tell me what is currently displayed on my screen': 'read',
      "Open Chrome and search for today's gold price": 'search',
      'Open Settings and open Bluetooth': 'search',
      'Open Instagram and search for Rahul': 'search'
    };
    for (final e in tasks.entries) {
      expect(AgentGoal.parse(e.key)?.workflow, e.value, reason: e.key);
    }
  });
  test(
      'YouTube search focus type submit result',
      () async => route('Open YouTube and search cats', yt, [
            [n('Search', 'search', desc: 'Search')],
            [n('', 'search_edit', edit: true, focus: true)],
            [n('cats', 'search_edit', edit: true, focus: true)],
            [n('cats video', 'video_title'), n('Filters', 'filters')]
          ], [
            'tap',
            'type',
            'submit'
          ]));
  test(
      'YouTube play waits for verified player and audio',
      () async => route(
          'Open YouTube and play cats',
          yt,
          [
            [n('cats video', 'video_title'), n('Filters', 'filters')],
            [n('cats video', 'video_title'), n('', 'pause', desc: 'Pause')]
          ],
          ['tap'],
          audio: true));
  test(
      'Chrome focus type submit exact URL result',
      () async => route('Open Chrome and search cats', chrome, [
            [n('', 'url_bar')],
            [n('', 'url_bar', edit: true, focus: true)],
            [n('cats', 'url_bar', edit: true, focus: true)],
            [n('https://www.google.com/search?q=cats', 'url_bar')]
          ], [
            'tap',
            'type',
            'submit'
          ]));
  test(
      'Instagram search opens focuses types submits result',
      () async => route('Open Instagram and search Rahul', ig, [
            [n('Search', 'search')],
            [n('', 'search_edit', edit: true, focus: true)],
            [n('Rahul', 'search_edit', edit: true, focus: true)],
            [n('Rahul', 'username'), n('Accounts', 'tab')]
          ], [
            'tap',
            'type',
            'submit'
          ]));
  test(
      'ChatGPT exact prompt submits once and verifies generating',
      () async => route('Open ChatGPT and search for explain gravity', gpt, [
            [n('', 'composer', edit: true)],
            [n('', 'composer', edit: true, focus: true)],
            [
              n('explain gravity', 'composer', edit: true),
              n('', 'send', desc: 'Send prompt')
            ],
            [n('explain gravity', 'user_message'), n('Thinking', 'status')]
          ], [
            'tap',
            'type',
            'submit'
          ]));
  test(
      'Bluetooth opens page, never toggles switch',
      () async => route('Open Settings and open Bluetooth', settings, [
            [n('Bluetooth', 'title')],
            [n('Bluetooth', 'title'), n('Pair new device', 'pair')]
          ], [
            'tap'
          ]));
  for (final wording in [
    'Open WhatsApp and open my chat with Rahul',
    'WhatsApp open chat search rahul'
  ]) {
    test('WhatsApp existing wrong conversation to global chat: $wording',
        () async {
      final q = AgentGoal.parse(wording)!.query;
      await route(wording, wa, [
        [n('Priya', 'conversation_contact_name'), n('', 'entry', edit: true)],
        [n('Search', 'search')],
        [n('', 'search_src_text', edit: true, focus: true)],
        [
          n(q, 'search_src_text', edit: true, focus: true),
          n(q, 'contact_name')
        ],
        [n(q, 'conversation_contact_name'), n('', 'entry', edit: true)]
      ], [
        'back',
        'tap',
        'type',
        'tap'
      ]);
    });
  }
  test(
      'WhatsApp search is not composer typing',
      () async => route('Open WhatsApp and search Rahul', wa, [
            [n('Search', 'search')],
            [n('', 'search_src_text', edit: true, focus: true)],
            [
              n('Rahul', 'search_src_text', edit: true, focus: true),
              n('Rahul', 'contact_name')
            ]
          ], [
            'tap',
            'type'
          ]));
  for (final pkg in [wa, yt, chrome, ig, gpt, settings]) {
    test('missing controls in $pkg cannot invoke model or invent a tap',
        () async {
      final goal = AgentGoal('', pkg, 'Rahul',
          settings: pkg == settings,
          workflow: pkg == wa ? 'contact' : 'search');
      final m = NoModel();
      final a = await LocalBrain(m).decide(
          goal, s(pkg, []), ['Step 1 wait: verified', 'Step 2 wait: verified']);
      expect(a.action, 'ask_confirmation');
      expect(m.calls, 0);
    });
  }
  test('wrong contact, duplicate contacts, partial matches never complete', () {
    final goal = AgentGoal.parse('Open WhatsApp and open my chat with Rahul')!;
    expect(
        FridayAgent.complete(
            goal,
            s(wa, [
              n('Rahul Sharma', 'conversation_contact_name'),
              n('', 'entry', edit: true)
            ])),
        false);
    final a = WorkflowPlanner.next(
        goal,
        s(wa, [
          n('Rahul', 'search_src_text', edit: true, focus: true),
          n('Rahul', 'contact_name'),
          n('Rahul', 'contact_name2')
        ]));
    expect(a?.action, 'ask_confirmation');
  });
  test('WhatsApp search field is never conversation completion evidence', () {
    final g = AgentGoal.parse('Open WhatsApp and open my chat with Rahul')!;
    expect(
        FridayAgent.complete(
            g,
            s(wa, [
              n('Rahul', 'contact_title'),
              n('Rahul', 'search_edit', edit: true, focus: true)
            ])),
        false);
  });
  test('task aliases never authorize send or fuzzy contact identity', () {
    for (final task in [
      'WhatsApp send Rahul hi',
      'WhatsApp open chat search Rahul and send hi',
      'Open WhatsApp and search Rahul chat and delete it'
    ]) expect(AgentGoal.parse(task), isNull);
  });
  test('Bluetooth menu presence alone is not completion', () {
    final g = AgentGoal.parse('Open Settings and open Bluetooth')!;
    final before = s(settings, [n('Bluetooth', 'title')]);
    final a = WorkflowPlanner.next(g, before)!;
    expect(FridayAgent.verify(a, before, before: before), false);
    expect(FridayAgent.complete(g, before), false);
  });
  test('scroll refuses ambiguous panes', () {
    final a = FridayAgent.commandAction(
        AgentAction(action: 'scroll', text: 'down'),
        s(wa, [
          {
            'scrollable': true,
            'bounds': [0, 0, 100, 100]
          },
          {
            'scrollable': true,
            'bounds': [100, 0, 200, 100]
          }
        ]),
        wa);
    expect(a.action, 'ask_confirmation');
  });
}
