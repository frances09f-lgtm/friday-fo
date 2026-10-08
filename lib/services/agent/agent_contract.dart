import 'dart:convert';

class AgentAction {
  final String action;
  final Map<String, dynamic> target;
  final String text, reason;
  final double confidence;
  final Map<String, dynamic> expect;
  AgentAction(
      {required this.action,
      this.target = const {},
      this.text = '',
      this.reason = '',
      this.confidence = 0,
      this.expect = const {}});
  static const actions = {
    'tap',
    'long_press',
    'swipe',
    'scroll',
    'type',
    'back',
    'home',
    'open_app',
    'wait',
    'read_screen',
    'finish',
    'ask_confirmation'
  };
  factory AgentAction.parse(String raw) {
    final m = jsonDecode(raw) as Map<String, dynamic>;
    if (!actions.contains(m['action']))
      throw const FormatException('Unknown action');
    if (m.containsKey('x') || m.containsKey('y'))
      throw const FormatException('Coordinates disabled in core V1');
    final t = m['target'];
    return AgentAction(
        action: m['action'],
        target: t is Map
            ? Map<String, dynamic>.from(t)
            : t is String
                ? {'text': t}
                : {},
        text: m['text']?.toString() ?? '',
        reason: m['reason']?.toString() ?? '',
        confidence: (m['confidence'] as num?)?.toDouble() ?? 0,
        expect:
            m['expect'] is Map ? Map<String, dynamic>.from(m['expect']) : {});
  }
  Map<String, dynamic> json() => {
        'action': action,
        'target': target,
        'text': text,
        'reason': reason,
        'confidence': confidence,
        'expect': expect
      };
}

class AgentGoal {
  final String task, package, query;
  final bool settings;
  const AgentGoal(this.task, this.package, this.query, {this.settings = false});
  static AgentGoal? parse(String task) {
    final s = task.trim();
    final settings = RegExp(r'^open settings and open bluetooth[.!]?$',
        caseSensitive: false);
    if (settings.hasMatch(s))
      return AgentGoal(s, 'com.android.settings', 'Bluetooth', settings: true);
    final m = RegExp(
            r'^open (youtube|chrome|instagram) and search (?:for )?(.+?)[.!]?$',
            caseSensitive: false)
        .firstMatch(s);
    if (m == null) return null;
    final query = m[2]!.trim();
    if (query.length > 120 || query.contains('\n')) return null;
    return AgentGoal(
        s,
        {
          'youtube': 'com.google.android.youtube',
          'chrome': 'com.android.chrome',
          'instagram': 'com.instagram.android'
        }[m[1]!.toLowerCase()]!,
        query);
  }

  bool permits(AgentAction a) {
    if (a.action == 'ask_confirmation' ||
        a.action == 'wait' ||
        a.action == 'read_screen' ||
        a.action == 'finish') return true;
    if (a.action == 'open_app') return a.target['package'] == package;
    if (a.action == 'home' || a.action == 'back') return true;
    if (a.action == 'type') return !settings && a.text == query;
    if (a.action == 'long_press') return false;
    if (a.action == 'scroll' || a.action == 'swipe') return !settings;
    if (a.action == 'tap') {
      final value =
          '${a.target['text'] ?? ''} ${a.target['contentDescription'] ?? ''} ${a.target['resourceId'] ?? ''}'
              .trim()
              .toLowerCase();
      if (settings) return value == 'bluetooth';
      return value.isNotEmpty &&
          RegExp(r'search|검색|search_box|search_edit|url_bar|address|omnibox')
              .hasMatch(value) &&
          !RegExp(r'send|post|buy|delete|permission|allow|call')
              .hasMatch(value);
    }
    return false;
  }
}
