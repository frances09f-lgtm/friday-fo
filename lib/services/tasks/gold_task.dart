/// A narrow, on-device task. The command parser never uses a cloud model.
class GoldTaskRequest {
  const GoldTaskRequest(this.direction, this.threshold, this.intervalMinutes);
  final String direction;
  final double threshold;
  final int intervalMinutes;

  static bool isAlertRequest(String text) => RegExp(
          r'\b(ping|alert|notify|tell)\b.*\b(when|if)\b.*\b(gold|xau)\b|\b(gold|xau)\b.*\b(alert|notify|ping)\b',
          caseSensitive: false)
      .hasMatch(text);
  static GoldTaskRequest? parse(String text) {
    final short = RegExp(
            r'^(?:ping|alert|notify|tell) me (?:if|when) (?:gold|xau)(?: price)? (?:goes |drops |rises |is |falls )?(below|above) (?:\$|usd\s*)?(\d+(?:\.\d+)?)[.!]?$',
            caseSensitive: false)
        .firstMatch(text.trim());
    if (short != null) {
      final n = double.tryParse(short[2]!);
      if (n != null && n.isFinite && n > 0)
        return GoldTaskRequest(short[1]!.toLowerCase(), n, 5);
    }

    final match = RegExp(
      r'^check\s+gold\s+every\s+(?:(\d+)\s*(minutes?|mins?|hours?|hrs?)|(hour))\s+and\s+(?:tell|notify|alert)\s+me\s+(?:if|when)\s+(?:it|gold|the price)\s+(?:goes|drops|rises|is)\s+(below|above)\s+(\d+(?:\.\d+)?)[.!]?$',
      caseSensitive: false,
    ).firstMatch(text.trim());
    if (match == null) return null;
    var minutes = match.group(3) != null ? 60 : int.parse(match.group(1)!);
    if (match.group(2)?.toLowerCase().startsWith('h') == true) minutes *= 60;
    final threshold = double.tryParse(match.group(5)!);
    if (minutes < 5 ||
        minutes > 1440 ||
        threshold == null ||
        !threshold.isFinite ||
        threshold <= 0) return null;
    return GoldTaskRequest(match.group(4)!.toLowerCase(), threshold, minutes);
  }

  Map<String, dynamic> toJson() => {
        'direction': direction,
        'threshold': threshold,
        'intervalMinutes': intervalMinutes,
      };
}
