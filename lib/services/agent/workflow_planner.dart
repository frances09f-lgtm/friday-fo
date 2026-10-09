import 'agent_contract.dart';

/// Deterministic recovery for known workflows. Only unique observed controls are
/// proposed. No hardcoded coordinates, no send-message fallback, no fuzzy contacts.
class WorkflowPlanner {
  static AgentAction? next(AgentGoal g, Map<String, dynamic> screen) {
    final es = ((screen['elements'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    AgentAction? choose(String action, List<Map<String, dynamic>> candidates,
        {String? expected, String text = ''}) {
      if (candidates.length != 1) return null;
      final e = candidates.single;
      final target = <String, dynamic>{};
      for (final key in ['resourceId', 'contentDescription', 'text']) {
        final value = e[key]?.toString() ?? '';
        if (value.isNotEmpty) {
          target[key] = value;
        }
      }
      if (target.isEmpty) return null;
      final proposed = AgentAction(
          action: action,
          target: target,
          text: text,
          confidence: 1,
          reason: 'Unique observed workflow control',
          expect: {
            'package': g.package,
            if (action == 'type') 'textEquals': text,
            if (expected != null) 'contains': expected
          });
      return g.permits(proposed) ? proposed : null;
    }

    String label(Map<String, dynamic> e) =>
        '${e['text'] ?? ''} ${e['contentDescription'] ?? ''} ${e['resourceId'] ?? ''}';
    bool search(Map<String, dynamic> e) =>
        RegExp(r'search|url_bar|omnibox', caseSensitive: false)
            .hasMatch(label(e));
    if (screen['package'] == null) return null;
    if (screen['package'] != g.package)
      return AgentAction(
          action: 'open_app',
          target: {'package': g.package},
          confidence: 1,
          expect: {'package': g.package});
    if (es.any((e) =>
        AgentGoal.unsafeLabel(label(e)) &&
        RegExp(r'login|log.?in|sign.?in|permission|allow', caseSensitive: false)
            .hasMatch(label(e)))) return null;
    if (g.workflow == 'question') {
      final sent = es.any((e) => e['editable'] != true && e['text'] == g.query);
      if (sent)
        return null; // Wait for explicit response evidence, don't duplicate submit.
      final fields = es.where((e) => e['editable'] == true).toList();
      if (fields.length != 1) return null;
      if (fields.single['text'] == g.query) {
        return choose(
            'submit',
            es
                .where((e) => RegExp(
                        r'^(send|send prompt|send message|submit)$',
                        caseSensitive: false)
                    .hasMatch((e['contentDescription'] ?? e['text'] ?? '')
                        .toString()))
                .toList(),
            text: g.query);
      }
      return choose('type', fields, text: g.query);
    }
    final fields = es.where((e) => e['editable'] == true && search(e)).toList();
    if (fields.length == 1) {
      if (fields.single['text'] != g.query)
        return choose('type', fields, text: g.query);
      final result = es.any((e) =>
          e['editable'] != true &&
          '${e['text'] ?? ''}'.toLowerCase().contains(g.query.toLowerCase()));
      if (!result) return choose('submit', fields, text: g.query);
    }
    if (g.workflow == 'contact') {
      final contacts = es
          .where((e) =>
              e['editable'] != true &&
              e['text']?.toString().toLowerCase() == g.query.toLowerCase())
          .toList();
      if (contacts.isNotEmpty)
        return choose('tap', contacts, expected: g.query);
    }
    if (g.workflow == 'play') {
      final videos = es
          .where((e) =>
              e['editable'] != true &&
              label(e).toLowerCase().contains(g.query.toLowerCase()) &&
              !search(e))
          .toList();
      // Several relevant results require the local planner or user selection.
      if (videos.isNotEmpty) return choose('tap', videos, expected: g.query);
    }
    return choose(
        'tap',
        es
            .where((e) =>
                search(e) &&
                e['editable'] != true &&
                !AgentGoal.unsafeLabel(label(e)))
            .toList(),
        expected: 'Search');
  }
}
