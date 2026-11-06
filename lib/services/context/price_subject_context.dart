import '../tasks/gold_task.dart';

/// A recent, successfully answered price query can supply only an alert's
/// subject. Never carries a direction, amount, interval or trade parameters.
class PriceSubjectContext {
  DateTime? _at;
  String? _asset;
  void remember(String asset, DateTime now) {
    _asset = asset;
    _at = now;
  }

  void clear() {
    _asset = null;
    _at = null;
  }

  String? resolve(String text, DateTime now) {
    if (_at == null ||
        now.isBefore(_at!) ||
        now.difference(_at!) >= const Duration(minutes: 5) ||
        !GoldTaskRequest.isAssetlessAlert(text)) return null;
    // A complete placeholder subject, not a fragment of another named asset.
    final placeholder = RegExp(
        r'\b(?:when|if|once|as soon as)\s+((?:it|(?:the )?(?:price|rate)))\s+(?=(?:goes?|is|gets?|moves?|rises?|falls?|drops?|hits?|reaches?|crosses?|touches?)\b)',
        caseSensitive: false);
    final m = placeholder.firstMatch(text);
    if (m == null) return null;
    return text.replaceRange(m.start + m[0]!.indexOf(m[1]!),
        m.start + m[0]!.indexOf(m[1]!) + m[1]!.length, _asset!);
  }
}
