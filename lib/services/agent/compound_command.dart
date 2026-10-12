/// Splits a user compound command without pretending arbitrary apps have an
/// automation recipe. The action is data until a supported workflow accepts it.
class CompoundCommand {
  const CompoundCommand(this.app, this.action);
  final String app, action;
  static CompoundCommand? parse(String text) {
    final m = RegExp(r'^(?:please )?open (.+?) and (.+?)[.!?]?$',
            caseSensitive: false)
        .firstMatch(text.trim());
    if (m == null || m[1]!.length > 80 || m[2]!.length > 250) return null;
    return CompoundCommand(m[1]!.trim(), m[2]!.trim());
  }
}
