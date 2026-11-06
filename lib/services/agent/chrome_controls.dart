/// Deterministic Chrome-only control resolution. An arbitrary lone editor is
/// never treated as an address bar. Unknown/ambiguous editors fail closed.
class ChromeControls {
  static const canonicalIds = {
    'url_bar',
    'search_box_text',
    'omnibox_edit_text',
    'address_bar'
  };
  static String label(Map<String, dynamic> e) =>
      '${e['text'] ?? ''} ${e['contentDescription'] ?? ''} ${e['resourceId'] ?? ''} ${e['hintText'] ?? ''}';
  static bool clear(Map<String, dynamic> e) =>
      RegExp(r'clear|dismiss|close|reset', caseSensitive: false)
          .hasMatch(label(e));
  static bool canonical(Map<String, dynamic> e) {
    final id = (e['resourceId'] ?? '').toString();
    final parts = id.split(':id/');
    // Fully qualified IDs must belong to Chrome, not embedded web content.
    if (parts.length > 1 && parts.first != 'com.android.chrome') return false;
    return canonicalIds.contains(parts.last);
  }

  static List<Map<String, dynamic>> candidates(List<Map<String, dynamic>> es) {
    final editors = es.where((e) => e['editable'] == true).toList();
    // Multiple editors can be a form, including page login or payment fields.
    if (editors.length > 1) return [];
    final known = editors.where((e) => canonical(e) && !clear(e)).toList();
    if (known.length == 1) return known;
    final controls = es
        .where((e) =>
            !clear(e) &&
            RegExp(r'url_bar|search_box|omnibox|search or type|search or enter',
                    caseSensitive: false)
                .hasMatch(label(e)))
        .toList();
    final matchedEditors =
        controls.where((e) => e['editable'] == true).toList();
    if (matchedEditors.length == 1) return matchedEditors;
    if (editors.isNotEmpty) return [];
    return controls
        .where((e) => e['clickable'] == true && e['editable'] != true)
        .toList();
  }

  static String failure(List<Map<String, dynamic>> es) {
    if (es.where((e) => e['editable'] == true).length > 1)
      return 'chrome_multiple_editors';
    final c = candidates(es);
    if (c.length > 1) return 'chrome_ambiguous_navigation';
    if (c.length == 1) return 'chrome_target_rejected';
    if (es.any((e) => e['editable'] == true))
      return 'chrome_unrecognized_editor';
    return 'chrome_missing_navigation';
  }
}
