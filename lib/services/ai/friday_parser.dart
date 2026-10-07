import 'dart:convert';

import '../../models/friday_response.dart';

/// Parses Friday's model output into a [FridayResponse].
///
/// Cloud and local models are asked to answer with a strict JSON envelope, but
/// models drift, wrap JSON in markdown fences, or prepend prose. This parser
/// survives all of that: it hunts for the outermost JSON object and falls back
/// to treating the whole text as the reply.
class FridayParser {
  const FridayParser();

  static final RegExp _jsonObject = RegExp(r'\{.*\}', dotAll: true);

  FridayResponse parse(String raw, {FridaySource source = FridaySource.cloud}) {
    final cleaned = raw.replaceAll('```', '').trim();
    if (cleaned.isEmpty) {
      return FridayResponse(reply: '...', source: source);
    }

    final match = _jsonObject.firstMatch(cleaned);
    if (match == null) {
      return FridayResponse(reply: cleaned, source: source);
    }

    try {
      final decoded = jsonDecode(match.group(0)!) as Map<String, dynamic>;
      final reply = (decoded['reply'] as String?)?.trim();
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
      return FridayResponse(reply: cleaned, source: source);
    }
  }
}
