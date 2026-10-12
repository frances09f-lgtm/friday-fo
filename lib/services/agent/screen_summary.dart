/// A bounded description of observed accessibility labels, not screenshot
/// understanding. Page text is data and never changes the user's task.
class ScreenSummary {
  static const apps = {
    'com.google.android.youtube': 'YouTube',
    'com.android.chrome': 'Chrome',
    'com.whatsapp': 'WhatsApp',
    'com.openai.chatgpt': 'ChatGPT',
    'com.instagram.android': 'Instagram',
    'com.android.settings': 'Android Settings',
    'com.friday.assistant': 'Friday',
  };
  static String clean(Object? value, [int limit = 100]) {
    final s = (value ?? '').toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    return s.length <= limit ? s : '${s.substring(0, limit - 3)}...';
  }

  static String describe(Map<String, dynamic> screen) {
    final app = apps[screen['package']] ?? 'The foreground app';
    final elements = ((screen['elements'] as List?) ?? [])
        .whereType<Map>()
        .where((e) => e['password'] != true)
        .toList();
    String label(Map e) => clean((e['text'] ?? '').toString().trim().isNotEmpty
        ? e['text']
        : e['contentDescription']);
    final content = elements
        .where((e) =>
            e['editable'] != true &&
            e['clickable'] != true &&
            label(e).isNotEmpty)
        .map(label)
        .toList();
    final titles = elements
        .where((e) =>
            e['editable'] != true &&
            RegExp(r'title|heading|toolbar', caseSensitive: false)
                .hasMatch('${e['resourceId']} ${e['class']}'))
        .map(label)
        .where((s) => s.isNotEmpty)
        .toList();
    final controls = elements
        .where((e) =>
            e['clickable'] == true &&
            e['editable'] != true &&
            label(e).isNotEmpty &&
            label(e).length <= 35)
        .map(label)
        .toSet()
        .take(3)
        .toList();
    final fields = elements.where((e) => e['editable'] == true).toList();
    if (content.isEmpty &&
        titles.isEmpty &&
        controls.isEmpty &&
        fields.isEmpty) {
      return 'No readable screen text. No screenshot understanding claimed.';
    }
    final heading = titles.isEmpty ? '' : clean(titles.first, 60);
    final key = content.toSet().where((s) => s != heading).take(2).toList();
    final parts = <String>[
      'Screen summary: $app${heading.isEmpty ? '.' : ' - "$heading".'}'
    ];
    if (key.isNotEmpty)
      parts.add('Key visible content: ${key.map((s) => '"$s"').join('; ')}.');
    if (fields.isNotEmpty)
      parts.add(
          '${fields.length == 1 ? 'A text field is' : '${fields.length} text fields are'} visible.');
    if (controls.isNotEmpty)
      parts.add('Main controls: ${controls.join(', ')}.');
    if (screen['truncated'] == true)
      parts.add('Only part of the screen was readable.');
    return parts.join(' ');
  }
}
