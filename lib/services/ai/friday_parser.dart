import 'dart:convert';

import '../../models/friday_response.dart';

/// Parses Friday's model output into a [FridayResponse].
///
/// Cloud and local models are asked to answer with a strict JSON envelope, but
/// models drift, wrap JSON in markdown fences, change key casing, or prepend
/// prose. This parser survives all of that. The forgiving key/value handling
/// is adapted from OpenJarvis's NativeReActAgent parser
/// (github.com/open-jarvis/OpenJarvis, Apache-2.0): field names are matched
/// case-insensitively with separators ignored, and a malformed action is never
/// salvaged or executed - a broken envelope falls back to plain reply text.
class FridayParser {
  const FridayParser();

  static final RegExp _jsonObject = RegExp(r'\{.*\}', dotAll: true);

  // ReAct-style small-model drift: "Thought: ... Final Answer: <text>".
  static final RegExp _finalAnswer = RegExp(
    r'final\s*answer\s*:\s*(.+)$',
    dotAll: true,
    caseSensitive: false,
  );

  /// Field-name matching that forgives case, spaces, underscores, hyphens and
  /// camelCase: "Reply", " after_minutes ", "afterMinutes" all match.
  static String _key(String raw) =>
      raw.trim().toLowerCase().replaceAll(RegExp(r'[-_\s]'), '');

  static Map<String, dynamic> _normalizeKeys(Map<String, dynamic> json) {
    final out = <String, dynamic>{};
    json.forEach((key, value) {
      out.putIfAbsent(_key(key), () => value);
    });
    return out;
  }

  FridayResponse parse(String raw, {FridaySource source = FridaySource.cloud}) {
    final cleaned = raw.replaceAll('```', '').trim();
    if (cleaned.isEmpty) {
      return FridayResponse(reply: '...', source: source);
    }

    final match = _jsonObject.firstMatch(cleaned);
    if (match == null) {
      // A small model may answer ReAct-style instead of JSON. Take its final
      // answer as the reply; never treat "Action:" text as an action.
      final fa = _finalAnswer.firstMatch(cleaned);
      if (fa != null && fa.group(1)!.trim().isNotEmpty) {
        return FridayResponse(reply: fa.group(1)!.trim(), source: source);
      }
      return FridayResponse(reply: cleaned, source: source);
    }

    try {
      final decoded = _normalizeKeys(
          jsonDecode(match.group(0)!) as Map<String, dynamic>);
      final reply = (decoded['reply'] as String?)?.trim() ??
          (decoded['response'] as String?)?.trim() ??
          (decoded['answer'] as String?)?.trim() ??
          (decoded['finalanswer'] as String?)?.trim();
      // Multi-part commands arrive as "actions":[...]; a single request
      // still arrives as "action":{...}. "actions" wins when both appear.
      final parsed = <FridayAction>[
        if (decoded['actions'] is List)
          for (final a in decoded['actions'] as List)
            if (a is Map<String, dynamic>) FridayAction.fromJson(a),
      ];
      final actionJson = decoded['action'];
      if (parsed.isEmpty && actionJson is Map<String, dynamic>) {
        parsed.add(FridayAction.fromJson(actionJson));
      }
      return FridayResponse(
        reply: reply == null || reply.isEmpty ? cleaned : reply,
        action: parsed.isEmpty ? const FridayAction() : parsed.first,
        extraActions: parsed.length > 1 ? parsed.sublist(1) : const [],
        source: source,
      );
    } on FormatException {
      // Broken JSON is never salvaged for actions; the raw text stands.
      return FridayResponse(reply: cleaned, source: source);
    }
  }
}
