import 'dart:convert';
import 'agent_contract.dart';

/// Bounded, goal-relevant model context. Native observation/act remains the
/// authority for package, freshness, uniqueness, safe bounds and protected UI.
class ScreenContext {
  static Map<String, dynamic> forGoal(
    AgentGoal goal,
    Map<String, dynamic> screen, {
    int limit = 40,
    int? maxChars,
  }) {
    final all = ((screen['elements'] as List?) ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final words = goal.query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 1)
        .toSet();
    int score(Map<String, dynamic> e) {
      final label =
          '${e['text'] ?? ''} ${e['contentDescription'] ?? ''} ${e['resourceId'] ?? ''}'
              .toLowerCase();
      return (e['editable'] == true ? 30 : 0) +
          (e['focused'] == true ? 15 : 0) +
          (e['clickable'] == true ? 8 : 0) +
          (e['scrollable'] == true ? 10 : 0) +
          (RegExp(
            r'search|url_bar|omnibox|toolbar|title|player|composer|prompt',
          ).hasMatch(label)
              ? 20
              : 0) +
          words.where(label.contains).length * 12;
    }

    final indices = List<int>.generate(all.length, (i) => i);
    indices.sort((a, b) {
      final c = score(all[b]).compareTo(score(all[a]));
      return c != 0 ? c : a.compareTo(b);
    });
    // Most slots go to relevant controls, the rest sample the whole tree so
    // lower-page/unknown labels are not always lost to top navigation chrome.
    final selected = indices.take((limit * .75).floor()).toSet();
    final remaining = List<int>.generate(
      all.length,
      (i) => i,
    ).where((i) => !selected.contains(i)).toList();
    final slots = limit - selected.length;
    for (var i = 0; i < slots && i < remaining.length; i++) {
      selected.add(remaining[(i * remaining.length / slots).floor()]);
    }
    final records = <int, Map<String, dynamic>>{};
    var used = 0;
    // Preserve exact semantic labels. Skip a whole over-budget element rather
    // than truncating a target into a label Android cannot match.
    for (final i in indices.where(selected.contains)) {
      final record = <String, dynamic>{
        'id': all[i]['id'] ?? 'observed-$i',
        for (final key in [
          'text',
          'contentDescription',
          'resourceId',
          'editable',
          'clickable',
          'scrollable',
          'focused',
          'bounds',
          'parentContext'
        ])
          if (all[i][key] != null && all[i][key] != '' && all[i][key] != false)
            key: all[i][key],
      };
      final cost = jsonEncode(record).length + 1;
      if (maxChars != null && used + cost > maxChars - 180) continue;
      used += cost;
      records[i] = record;
    }
    final ordered = records.keys.toList()..sort();
    return {
      'package': screen['package'],
      'observedCount': all.length,
      'omittedCount': all.length - ordered.length,
      'truncated': screen['truncated'] == true || ordered.length < all.length,
      'elements': ordered.map((i) => records[i]).toList(),
    };
  }

  static bool scrollMoved(
    AgentAction action,
    Map<String, dynamic> before,
    Map<String, dynamic> after,
  ) {
    // A spinner, focus change or unrelated screen token is not scroll proof.
    final old = before['scrollEvent'];
    final now = after['scrollEvent'];
    if (now is! Map ||
        now['revision'] == null ||
        (old is Map && old['revision'] == now['revision'])) return false;
    if (now['package'] != after['package']) return false;
    final containers = ((before['elements'] as List?) ?? [])
        .where(
          (e) =>
              e['scrollable'] == true &&
              action.target.entries
                  .where(
                    (t) => {
                      'text',
                      'resourceId',
                      'contentDescription',
                      'bounds',
                    }.contains(t.key),
                  )
                  .every((t) => _same(e[t.key], t.value)),
        )
        .toList();
    if (containers.length != 1 ||
        !_same(containers.single['bounds'], now['bounds'])) return false;
    return now['moved'] == true &&
        (action.text == 'up'
            ? now['direction'] == 'up'
            : now['direction'] == 'down');
  }

  static bool _same(dynamic a, dynamic b) =>
      a is List && b is List ? a.toString() == b.toString() : a == b;
}
