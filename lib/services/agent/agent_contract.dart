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
    'submit',
    'search_intent',
    'ask_confirmation'
  };
  factory AgentAction.parse(String raw) {
    var source = raw.trim();
    if (source.startsWith('```')) {
      final fenced =
          RegExp(r'^```(?:json)?\s*([\s\S]*?)\s*```$', caseSensitive: false)
              .firstMatch(source);
      if (fenced == null)
        throw const FormatException('Expected one JSON object');
      source = fenced[1]!;
    }
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic>)
      throw const FormatException('Expected one JSON object');
    final m = Map<String, dynamic>.from(decoded);
    if (m['action'] is String)
      m['action'] =
          (m['action'] as String).trim().toLowerCase().replaceAll(' ', '_');
    if (!actions.contains(m['action']))
      throw const FormatException('Unknown action');
    if (m.containsKey('x') || m.containsKey('y'))
      throw const FormatException('Coordinates disabled in core V1');
    final t = m['target'];
    if (t is Map && (t.containsKey('x') || t.containsKey('y')))
      throw const FormatException('Coordinates disabled in core V1');
    if (m['confidence'] != null && m['confidence'] is! num)
      throw const FormatException('Confidence must be a number');
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
  final bool firstVideo;
  final String workflow;
  final List<AgentAction> commands;
  const AgentGoal(this.task, this.package, this.query,
      {this.settings = false,
      this.firstVideo = false,
      this.workflow = 'search',
      this.commands = const []});
  static AgentGoal? parse(String task) {
    var s = task.trim().replaceAll(RegExp(r'\s+'), ' ');
    final ask =
        RegExp(r'^(?:please )?ask chat\s*gpt (.+?)[.!]?$', caseSensitive: false)
            .firstMatch(s);
    final on = RegExp(
            r'^(?:please )?search (?:for )?(.+?) (?:on|in|using) chat\s*gpt[.!]?$',
            caseSensitive: false)
        .firstMatch(s);
    if (ask != null || on != null) {
      final query = (ask?[1] ?? on![1]!).trim();
      if (query.isEmpty || query.length > 250 || query.contains('\n'))
        return null;
      return AgentGoal(task.trim(), 'com.openai.chatgpt', query,
          workflow: 'question');
    }
    s = s.replaceAll(RegExp(r'chat\s+gpt', caseSensitive: false), 'ChatGPT');
    final settings = RegExp(r'^open settings and open bluetooth[.!]?$',
        caseSensitive: false);
    if (settings.hasMatch(s))
      return AgentGoal(s, 'com.android.settings', 'Bluetooth', settings: true);
    if (RegExp(
            r'^(?:(?:tell me )?what is (?:currently )?(?:displayed )?on my screen|(?:please )?(?:read|describe) (?:my |the )?screen|(?:can you )?(?:please )?(?:read|describe) (?:my |the )?screen)[.!?]?$',
            caseSensitive: false)
        .hasMatch(s)) {
      return AgentGoal(s, '', '', workflow: 'read');
    }
    final pieces = s
        .replaceFirst(RegExp(r'^go ', caseSensitive: false), '')
        .split(RegExp(r',?\s+and\s+|,\s*', caseSensitive: false));
    final commands = <AgentAction>[];
    for (final piece in pieces) {
      final part = piece.trim().replaceFirst(RegExp(r'[.!]$'), '');
      if (part.toLowerCase() == 'back') {
        commands.add(AgentAction(action: 'back', confidence: 1));
      } else if (RegExp(r'^(?:scroll|swipe) (?:up|down)$', caseSensitive: false)
          .hasMatch(part)) {
        commands.add(AgentAction(
            action: part.split(' ').first.toLowerCase(),
            text: part.split(' ').last.toLowerCase(),
            confidence: 1));
      } else {
        final t =
            RegExp(r'^(tap|type) (.+)$', caseSensitive: false).firstMatch(part);
        if (t == null || t[2]!.length > 250) {
          commands.clear();
          break;
        }
        final value = t[2]!.replaceAll(RegExp(r'^"|"$'), '');
        commands.add(AgentAction(
            action: t[1]!.toLowerCase(),
            target: t[1]!.toLowerCase() == 'tap' ? {'text': value} : {},
            text: t[1]!.toLowerCase() == 'type' ? value : '',
            confidence: 1));
      }
    }
    if (commands.isNotEmpty && commands.length <= 8)
      return AgentGoal(s, '', '', workflow: 'commands', commands: commands);
    // Explicit chat-search aliases only. Never interpret message/send requests
    // as navigation, and never infer or fuzzy-match the recipient.
    final shortContact = RegExp(
            r'^(?:please )?(?:open )?whatsapp open (?:my )?chat (?:search|with) (.+?)[.!]?$',
            caseSensitive: false)
        .firstMatch(s);
    final searchChat = RegExp(
            r'^(?:please )?open whatsapp and search (?:for )?(.+?) chat[.!]?$',
            caseSensitive: false)
        .firstMatch(s);
    final contact = (shortContact?[1] ?? searchChat?[1])?.trim();
    if (contact != null && unsafeLabel(contact)) return null;
    if (RegExp(r'\band (?:send|delete|pay|buy|purchase|call|post|confirm)\b',
            caseSensitive: false)
        .hasMatch(s)) return null;
    if (contact != null &&
        contact.isNotEmpty &&
        contact.length <= 120 &&
        !unsafeLabel(contact)) {
      return AgentGoal(s, 'com.whatsapp', contact, workflow: 'contact');
    }
    final wa = RegExp(r'^open whatsapp and open (?:my )?chat with (.+?)[.!]?$',
            caseSensitive: false)
        .firstMatch(s);
    if (wa != null && wa[1]!.trim().length <= 120)
      return AgentGoal(s, 'com.whatsapp', wa[1]!.trim(), workflow: 'contact');
    final compound = RegExp(
            r'^(?:please )?open youtube(?: and)? search(?: for)? (.+?) and play (?:the )?first video[.!?]?$',
            caseSensitive: false)
        .firstMatch(s);
    if (compound != null) {
      final query = compound[1]!.trim();
      if (query.isEmpty || query.length > 200 || query.contains('\n'))
        return null;
      return AgentGoal(s, 'com.google.android.youtube', query,
          workflow: 'play', firstVideo: true);
    }
    final m = RegExp(
            r'^open (youtube|chrome|instagram|chatgpt|whatsapp) and (search(?: for)?|play|ask) (.+?)[.!]?$',
            caseSensitive: false)
        .firstMatch(s);
    if (m == null) return null;
    final query = m[3]!.trim();
    if (query.isEmpty || query.length > 250 || query.contains('\n'))
      return null;
    final app = m[1]!.toLowerCase();
    if (m[2]!.toLowerCase() == 'play' && app != 'youtube') return null;
    return AgentGoal(
        s,
        {
          'youtube': 'com.google.android.youtube',
          'chrome': 'com.android.chrome',
          'instagram': 'com.instagram.android',
          'chatgpt': 'com.openai.chatgpt',
          'whatsapp': 'com.whatsapp'
        }[app]!,
        query,
        workflow: app == 'chatgpt'
            ? 'question'
            : m[2]!.toLowerCase() == 'play'
                ? 'play'
                : 'search');
  }

  AgentGoal withPackage(String pkg) => AgentGoal(task, pkg, query,
      settings: settings,
      workflow: workflow,
      commands: commands,
      firstVideo: firstVideo);
  bool get noPlanner =>
      workflow == 'read' ||
      workflow == 'commands' ||
      settings ||
      {
        'com.whatsapp',
        'com.google.android.youtube',
        'com.android.chrome',
        'com.instagram.android',
        'com.openai.chatgpt'
      }.contains(package);
  static bool unsafeLabel(String value) => RegExp(
          r'\b(send|post|buy|purchase|delete|pay|call|allow|permission|sign.?in|log.?in|subscribe|confirm)\b',
          caseSensitive: false)
      .hasMatch(value);

  bool permits(AgentAction a) {
    if (a.action == 'ask_confirmation' ||
        a.action == 'wait' ||
        a.action == 'read_screen' ||
        a.action == 'finish') return true;
    if (a.action == 'search_intent')
      return {'com.google.android.youtube', 'com.android.chrome'}
              .contains(package) &&
          {'search', 'play'}.contains(workflow) &&
          a.text == query &&
          a.target['package'] == package &&
          query.isNotEmpty &&
          query.length <= 200;
    if (a.action == 'open_app') return a.target['package'] == package;
    if (a.action == 'home') return false;
    if (a.action == 'back')
      return (workflow == 'commands' &&
              commands.any((c) => c.action == 'back')) ||
          (package == 'com.whatsapp' &&
              {'contact', 'search'}.contains(workflow) &&
              a.expect['whatsappConversationExit'] == true);
    if (a.action == 'type')
      return !settings &&
          (workflow == 'commands'
              ? commands.any((c) => c.action == 'type' && c.text == a.text)
              : a.text == query);
    if (a.action == 'submit')
      return workflow == 'question' ||
          workflow == 'search' ||
          workflow == 'play' ||
          workflow == 'contact';
    if (a.action == 'long_press') return false;
    if (a.action == 'scroll' || a.action == 'swipe') return !settings;
    if (a.action == 'tap') {
      final value =
          '${a.target['text'] ?? ''} ${a.target['contentDescription'] ?? ''} ${a.target['resourceId'] ?? ''} ${a.target['hintText'] ?? ''}'
              .trim()
              .toLowerCase();
      if (settings)
        return a.target['text']?.toString().toLowerCase() == 'bluetooth' &&
            !unsafeLabel(value);
      if (unsafeLabel(value)) return false;
      if (workflow != 'commands' &&
          RegExp(r'clear|dismiss|close|reset', caseSensitive: false)
              .hasMatch(value)) return false;
      if (workflow == 'commands')
        return commands.any(
            (c) => c.action == 'tap' && c.target['text'] == a.target['text']);
      if (workflow == 'contact' &&
          a.target['text']?.toString().toLowerCase() == query.toLowerCase())
        return true;
      if (workflow == 'question')
        return RegExp(r'message|prompt|composer|ask|edittext').hasMatch(value);
      if (workflow == 'play' && value.contains(query.toLowerCase()))
        return true;
      return value.isNotEmpty &&
          RegExp(r'search|검색|search_box|search_edit|url_bar|address|omnibox')
              .hasMatch(value) &&
          !RegExp(r'send|post|buy|delete|permission|allow|call')
              .hasMatch(value);
    }
    return false;
  }
}
