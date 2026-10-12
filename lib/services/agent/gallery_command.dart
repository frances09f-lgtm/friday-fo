/// Operator-inspired bounded ordinal dispatch. First means newest-added media,
/// not the first tile in a particular gallery UI.
class GalleryCommand {
  static const words = {
    'first': 1,
    'second': 2,
    'third': 3,
    'fourth': 4,
    'fifth': 5,
    'sixth': 6,
    'seventh': 7,
    'eighth': 8,
    'ninth': 9,
    'tenth': 10
  };
  static int? parse(String text) {
    final m = RegExp(
            r'^(?:open (?:my )?gallery and |in (?:my )?gallery )?play (?:the )?([a-z]+|\d{1,2}(?:st|nd|rd|th)?) video(?: in (?:my )?gallery)?[.!?]?$',
            caseSensitive: false)
        .firstMatch(text.trim());
    if (m == null || !text.toLowerCase().contains('gallery')) return null;
    final value = m[1]!.toLowerCase();
    final n = words[value] ??
        int.tryParse(value.replaceAll(RegExp(r'(st|nd|rd|th)$'), ''));
    return n != null && n >= 1 && n <= 50 ? n : null;
  }
}
