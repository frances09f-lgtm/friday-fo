/// Read-only follow-up context. Never supplies parameters to an action.
class OroContext {
  DateTime? _at;
  String? _device;
  void remember(DateTime now, {String? device}) {
    _at = now;
    _device = device;
  }

  void clear() {
    _at = null;
    _device = null;
  }

  String? resolve(String text, DateTime now) {
    if (_at == null ||
        now.difference(_at!).inMinutes >= 5 ||
        now.isBefore(_at!)) return null;
    final t = text.trim().toLowerCase().replaceAll(RegExp(r'[.!?]+$'), '');
    String? query;
    if (RegExp(
            r'^(?:and |what about |how about )?(?:my |the )?(?:trade|trades|position|positions)$')
        .hasMatch(t)) query = 'my open trades';
    if (RegExp(
            r'^(?:(?:what is|what\x27s|and|what about) )?(?:my |the )?(?:tp|take profit)$')
        .hasMatch(t)) query = 'my trade TP';
    if (RegExp(
            r'^(?:(?:what is|what\x27s|and|what about) )?(?:my |the )?(?:sl|stop loss)$')
        .hasMatch(t)) query = 'my trade SL';
    if (RegExp(
            r'^(?:how much am i (?:losing|making)|(?:what is|what\x27s) my (?:p/l|pnl|profit|loss))$')
        .hasMatch(t)) query = 'my trade profit loss';
    if (query == null) return null;
    return _device == null ? query : '$query on my $_device';
  }
}
