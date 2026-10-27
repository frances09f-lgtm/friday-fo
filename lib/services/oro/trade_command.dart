/// Parses Friday trade commands for Sona's PAPER account ("buy gold 0.1 lot",
/// "sell 0.05 with SL 2310 TP 2280", "close my trade", "close all trades").
///
/// Pure and conservative: it only claims a message when every word is
/// trade vocabulary, so "buy milk" or "sell my old phone" are never read as
/// orders. A recognised order with something missing or unclear comes back
/// as a [TradeParse.question] instead of a guess - Friday never places an
/// order from an ambiguous parse.
library;

enum TradeOp { open, close }

class TradeCommand {
  const TradeCommand.open({
    required String this.side,
    required double this.lots,
    this.tp,
    this.sl,
    this.defaultSize = false,
  })  : op = TradeOp.open,
        all = false;

  const TradeCommand.close({this.side, this.all = false})
      : op = TradeOp.close,
        lots = null,
        tp = null,
        sl = null,
        defaultSize = false;

  /// open only: no size was said, so [lots] is the Default trade size from
  /// Settings (shown on the confirm card).
  final bool defaultSize;

  final TradeOp op;

  /// open: 'buy' / 'sell'. close: optional direction filter.
  final String? side;

  /// open only. Sona sizes in lots of 100 oz; 0.01 lot = 1 oz is the step.
  final double? lots;
  final double? tp;
  final double? sl;

  /// close only: close every matching open trade.
  final bool all;

  /// Sona stores quantity in ounces.
  double? get oz => lots == null ? null : (lots! * 100).roundToDouble();

  @override
  String toString() => op == TradeOp.open
      ? 'open $side $lots tp=$tp sl=$sl'
      : 'close side=$side all=$all';
}

/// The order side is known but the size is not yet: kept until the user
/// answers with a size ("0.05", "0.05 lot", "5 oz").
class TradeDraft {
  const TradeDraft({required this.side, this.tp, this.sl});
  final String side;
  final double? tp;
  final double? sl;
}

class TradeParse {
  const TradeParse.command(TradeCommand this.command)
      : question = null,
        draft = null,
        missingSize = false;
  const TradeParse.question(String this.question,
      {this.draft, this.missingSize = false})
      : command = null;

  final TradeCommand? command;
  final String? question;
  final TradeDraft? draft;

  /// The order is complete except for the size (none was said): the caller
  /// fills in the Default trade size instead of asking ("buy gold" buys).
  final bool missingSize;

  /// [draft] as an order at [lots] when only the size was missing.
  TradeCommand? withDefaultSize(double lots) => missingSize && draft != null
      ? TradeCommand.open(
          side: draft!.side,
          lots: lots,
          tp: draft!.tp,
          sl: draft!.sl,
          defaultSize: true)
      : null;
}

class TradeCommandParser {
  static const maxLots = 100.0;

  static const sizeHelp =
      'Say a size in lots, like "buy gold 0.01 lot" (1 lot = 100 oz, smallest is 0.01 lot = 1 oz).';

  /// Side known, size missing: Sona only trades gold (XAU/USD), so only the
  /// size is asked for.
  static String howMuch(String side) =>
      'How much gold do you want to ${side == 'sell' ? 'sell' : 'buy'}? For example "0.1 lot" (1 lot = 100 oz, smallest is 0.01 lot = 1 oz).';

  static const sideAndSize =
      'Buy or sell? Say "buy" or "sell" to use your default size, or add a size like "buy 0.1 lot" (Sona trades gold, XAU/USD).';

  /// Words of a vague trade intent with no size: "buy a trade", "sell a
  /// position", "buy a new paper trade".
  static const _vagueWords = {
    'a', 'an', 'new', 'paper', 'trade', 'position', 'order', 'some', 'one',
    'now', 'please', 'for', 'me',
  };
  static const _vagueAnchors = {'trade', 'position'};

  static final _num = r'(\d+(?:\.\d+)?|\.\d+)';

  static String _normalize(String text) {
    var t = ' ${text.toLowerCase()} ';
    t = t.replaceAll(RegExp(r'[\u2019`]'), "'");
    t = t.replaceAll(RegExp(r'xau\s*/\s*usd|xauusd|xau'), ' gold ');
    t = t.replaceAll(RegExp(r'\bs\s*/\s*l\b'), ' sl ');
    t = t.replaceAll(RegExp(r'\bt\s*/\s*p\b'), ' tp ');
    t = t.replaceAll(RegExp(r'\bstop[\s-]*loss\b|\bstoploss\b'), ' sl ');
    t = t.replaceAll(RegExp(r'\btake[\s-]*profit\b|\btakeprofit\b'), ' tp ');
    t = t.replaceAll(RegExp(r'\btarget\b'), ' tp ');
    t = t.replaceAll(RegExp(r'\bstop\b(?=\s*(?:at|@|=|:)?\s*\d)'), ' sl ');
    t = t.replaceAll(RegExp(r'\bounces?\b|\boz\.?(?=\s|$)'), ' oz ');
    t = t.replaceAll(RegExp(r'\blots?\b'), ' lot ');
    // "0.1lot" / "5oz"
    t = t.replaceAllMapped(RegExp(r'(\d)(lot|oz)\b'), (m) => '${m[1]} ${m[2]}');
    t = t.replaceAll(RegExp(r'[,!?;]'), ' ');
    t = t.replaceAll(RegExp(r'\.(?!\d)'), ' ');
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static final _lead = RegExp(
      r"^(?:(?:hey |ok |okay )?friday )?(?:please )?(?:(?:can|could|would) you (?:please )?)?(?:i want to |i'd like to |i would like to |let's |lets )?");

  static const _openFiller = {
    'gold', 'trade', 'position', 'order', 'paper', 'a', 'an', 'of', 'with',
    'and', 'market', 'now', 'please', 'for', 'me', 'in', 'on', 'sona', 'size',
    'qty', 'quantity', 'lot', 'oz', 'at', 'the', 'go', 'new', 'some',
  };

  static const _closeWords = {
    'my', 'the', 'all', 'every', 'both', 'open', 'gold', 'paper', 'trade',
    'trades', 'position', 'positions', 'order', 'orders', 'buy', 'buys',
    'sell', 'sells', 'long', 'longs', 'short', 'shorts', 'in', 'on', 'sona',
    'please', 'now', 'of', 'out', 'current', 'these', 'those', 'this', 'that',
    'it', 'them',
  };

  /// Null when [text] is not a trade command at all.
  static TradeParse? parse(String text) {
    var t = _normalize(text);
    t = t.replaceFirst(_lead, '');
    return _parseClose(t) ?? _parseOpen(t);
  }

  static TradeParse? _parseClose(String t) {
    final m = RegExp(r'^(?:close|exit|square ?off|flatten|get out of)\b(.*)$')
        .firstMatch(t);
    if (m == null) return null;
    final words =
        m[1]!.trim().split(' ').where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return null;
    if (words.any((w) => !_closeWords.contains(w))) return null;
    const anchors = {
      'trade', 'trades', 'position', 'positions', 'order', 'orders', 'gold',
      'buy', 'buys', 'sell', 'sells', 'long', 'longs', 'short', 'shorts',
    };
    if (!words.any(anchors.contains)) return null;
    String? side;
    final buy = words.any((w) => const {'buy', 'buys', 'long', 'longs'}.contains(w));
    final sell = words.any((w) => const {'sell', 'sells', 'short', 'shorts'}.contains(w));
    if (buy && sell) {
      side = null; // "close my buys and sells" = all
    } else if (buy) {
      side = 'buy';
    } else if (sell) {
      side = 'sell';
    }
    final all = words.any((w) => const {
          'all', 'every', 'both', 'trades', 'positions', 'orders', 'buys',
          'sells', 'longs', 'shorts', 'them', 'these', 'those',
        }.contains(w)) ||
        (buy && sell);
    return TradeParse.command(TradeCommand.close(side: side, all: all));
  }

  static TradeParse? _parseOpen(String t) {
    // "open a trade", "place a trade", "make a new gold trade": a trade with
    // neither side nor size. Ask for both; never guess.
    if (RegExp(
            r'^(?:open|place|take|make|start|enter|do|put)(?: me)?(?: a| an)?(?: new)?(?: paper)?(?: gold)? (?:trade|position)(?: (?:on|in|for|with) (?:gold|sona))?(?: (?:now|please))?$')
        .hasMatch(t)) {
      return const TradeParse.question(sideAndSize);
    }
    final m = RegExp(
            r'^(?:(?:open|place|take|put|make|do|enter)(?: me)?(?: a| an)?(?: new)?(?: paper)? )?(?:go )?(buy|sell|long|short)\b(.*)$')
        .firstMatch(t);
    if (m == null) return null;
    final side = (m[1] == 'buy' || m[1] == 'long') ? 'buy' : 'sell';
    var rest = ' ${m[2]!.trim()} ';
    final hadGold = rest.contains(' gold ');

    double? grab(String key) {
      final r = RegExp('\\s$key\\s*(?:at|@|=|:|of)?\\s*$_num(?=\\s)');
      final mm = r.firstMatch(rest);
      if (mm == null) return null;
      rest = rest.replaceRange(mm.start, mm.end, ' ');
      return double.tryParse(mm[1]!);
    }

    final hasSlWord = RegExp(r'\ssl\s').hasMatch(rest) || RegExp(r'\ssl\s*[\d.@=:]').hasMatch(rest);
    final hasTpWord = RegExp(r'\stp\s').hasMatch(rest) || RegExp(r'\stp\s*[\d.@=:]').hasMatch(rest);
    final sl = grab('sl');
    final tp = grab('tp');
    final looksLikeTrade = hadGold ||
        hasSlWord ||
        hasTpWord ||
        RegExp(r'\s(lot|oz)\s').hasMatch(rest);

    // A limit / pending order: Friday only sends market orders.
    if (RegExp(r'\slimit\s|\sstop order\s|\spending\s|\s(?:when|if) (?:price|gold|it)\s')
            .hasMatch(rest) ||
        RegExp('\\s(?:at|@)\\s*$_num(?=\\s)').hasMatch(rest)) {
      if (!looksLikeTrade && !RegExp('^\\s*$_num').hasMatch(rest)) return null;
      return const TradeParse.question(
          'Friday places market paper orders only. Set limit or pending orders in Sona itself.');
    }
    if ((hasSlWord && sl == null) || (hasTpWord && tp == null)) {
      if (!looksLikeTrade) return null;
      return const TradeParse.question(
          'I could not read the SL/TP price. Say it like "sell 0.05 lot SL 2310 TP 2280".');
    }

    // Size: the remaining number, with an optional unit.
    final sizes = RegExp('\\s$_num\\s*(lot|oz)?(?=\\s)').allMatches(rest).toList();
    final words = rest
        .replaceAll(RegExp('\\s$_num\\s*(lot|oz)?(?=\\s)'), ' ')
        .trim()
        .split(' ')
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.any((w) => !_openFiller.contains(w))) return null;
    if (!looksLikeTrade && sizes.length != 1) {
      // "buy" alone, or several bare numbers with no trade words.
      if (sizes.isEmpty && words.isEmpty) {
        // Bare "long"/"short" are ordinary words; "go long" is a trade.
        if ((m[1] == 'long' || m[1] == 'short') && !t.startsWith('go ')) {
          return null;
        }
        return TradeParse.question(howMuch(side),
            draft: TradeDraft(side: side), missingSize: true);
      }
      // "buy a trade", "sell a position": a trade intent without a size.
      if (sizes.isEmpty &&
          words.every(_vagueWords.contains) &&
          words.any(_vagueAnchors.contains)) {
        return TradeParse.question(howMuch(side),
            draft: TradeDraft(side: side), missingSize: true);
      }
      if (sizes.isEmpty) return null;
    }
    if (sizes.length > 1) {
      return const TradeParse.question(
          'I could not tell which number is the size, SL or TP. Say it like "sell 0.05 lot SL 2310 TP 2280".');
    }
    if (sizes.isEmpty) {
      return TradeParse.question(howMuch(side),
          draft: TradeDraft(side: side, tp: tp, sl: sl), missingSize: true);
    }
    final size = _size(sizes.first[1]!, sizes.first[2]);
    if (size.error != null) {
      return TradeParse.question(size.error!,
          draft: TradeDraft(side: side, tp: tp, sl: sl));
    }
    return TradeParse.command(
        TradeCommand.open(side: side, lots: size.lots!, tp: tp, sl: sl));
  }

  static ({double? lots, String? error}) _size(String n, String? unit) {
    final v = double.tryParse(n);
    if (v == null || !v.isFinite || v <= 0) {
      return (lots: null, error: 'The size must be above zero. $sizeHelp');
    }
    final lots = unit == 'oz' ? v / 100 : v;
    final steps = lots * 100;
    if ((steps - steps.roundToDouble()).abs() > 1e-6 || steps.round() < 1) {
      return (
        lots: null,
        error: 'Sona trades in steps of 0.01 lot (1 oz). $sizeHelp'
      );
    }
    if (lots > maxLots) {
      return (
        lots: null,
        error: '${_fmtLots(lots)} lots is more than the ${maxLots.toInt()}-lot limit for Friday orders. $sizeHelp'
      );
    }
    return (lots: steps.roundToDouble() / 100, error: null);
  }

  /// A usable Default trade size: above zero, a whole 0.01-lot step, within
  /// the per-order limit.
  static bool validDefaultLots(double lots) =>
      _size(lots.toString(), 'lot').error == null;

  /// A bare size answering "How much gold?" ("0.05", "0.05 lot", "5 oz").
  /// Returns lots, or an error/question; null when [text] is not a size.
  static ({double? lots, String? error})? parseSizeReply(String text) {
    var t = _normalize(text).replaceFirst(_lead, '');
    final m = RegExp('^(?:make it |size |just )?$_num\\s*(lot|oz)?(?: of gold| gold)?(?: please)?\$')
        .firstMatch(t);
    if (m == null) return null;
    return _size(m[1]!, m[2]);
  }

  static String _fmtLots(double lots) {
    final s = lots.toStringAsFixed(2);
    return s;
  }
}
