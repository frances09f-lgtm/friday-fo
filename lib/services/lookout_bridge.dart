import 'dart:convert';

class LookoutBridge {
  static String answer(String? raw, {int? nowMs}) {
    if (raw == null)
      return "I couldn't read Lookout. Install the bridge update and open Lookout once on this phone.";
    try {
      final j = jsonDecode(raw) as Map;
      final rows = (j['watches'] as List).whereType<Map>().toList();
      final total = (j['total'] as num).toInt();
      final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
      if (total == 0) return 'Lookout has no watches saved on this phone.';
      final counts = <String, int>{};
      for (final r in rows) {
        final s = r['status'] as String;
        counts[s] = (counts[s] ?? 0) + 1;
      }
      final lines = <String>[
        'Lookout: $total saved watches. ${counts.entries.map((e) => '${e.value} ${e.key}').join(', ')}${rows.length < total ? ' in the latest ${rows.length} watches' : ''}.'
      ];
      for (final r in rows.take(5)) {
        final checked = r['lastCheckedAt'] as num?;
        final age = checked == null
            ? 'never checked'
            : 'checked ${((now - checked.toInt()).clamp(0, 1 << 60) / 60000).floor()}m ago';
        final current = r['currentValue'] as num?;
        final value = current == null
            ? 'current value unavailable'
            : 'saved value $current';
        lines.add('#${r['id']} ${r['title']}: ${r['status']}, $age, $value.');
      }
      if (total > 5) lines.add('Open Lookout for the remaining watches.');
      lines.add('Saved results only; this does not run a fresh website check.');
      return lines.join('\n');
    } catch (_) {
      return "Lookout's saved data could not be read. Open Lookout and try again.";
    }
  }
}
