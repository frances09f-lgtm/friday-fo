// Adapted from Mobilerun sort_by_position in element_search.py (MIT).
// Copyright notice and license: third_party/mobilerun-MIT-LICENSE.txt.
// https://github.com/droidrun/mobilerun/blob/main/mobilerun/tools/helpers/element_search.py
class ElementOrder {
  /// Sort observed nodes top-to-bottom, then left-to-right. Caller must first
  /// validate four-element numeric bounds; this never invents screen positions.
  static int compare(Map<String, dynamic> a, Map<String, dynamic> b) {
    final top = (a['bounds'][1] as num).compareTo(b['bounds'][1] as num);
    return top != 0
        ? top
        : (a['bounds'][0] as num).compareTo(b['bounds'][0] as num);
  }
}
