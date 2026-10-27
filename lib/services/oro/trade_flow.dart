import 'dart:async';
import 'dart:convert';

import '../device/device_hub.dart';
import 'oro_bridge.dart';
import 'trade_command.dart';

/// Friday -> Sona paper-order path.
///
/// Friday never talks to Sona's backend and never sees Sona's PIN. It hands
/// the confirmed order to Sona's on-phone bridge (the same ContentProvider
/// Friday already reads, which only answers Friday's package), opens Sona,
/// and Sona places or closes the PAPER trade itself with its own session,
/// through the same openPaper/closePaper code as its Buy/Sell/Close buttons
/// (fresh-quote check, market hours, daily limits, margin, TP/SL sides).
/// Friday then reads Sona's answer back from the bridge.
abstract class OroTradeDesk {
  /// 'ok', 'missing' (Sona not installed), 'unsupported' (Sona too old),
  /// 'unavailable' (not an Android phone) or 'error'.
  Future<String> support();
  Future<OroSnapshot?> snapshot();

  /// Hands the order JSON to Sona and opens Sona. Same words as [support].
  Future<String> submit(String orderJson);

  /// Sona's result JSON for [id], or null while nothing is written yet.
  Future<String?> result(String id);
}

class DeviceOroTradeDesk implements OroTradeDesk {
  DeviceOroTradeDesk(this.hub);
  final DeviceHub hub;
  @override
  Future<String> support() => hub.oroTradeSupport();
  @override
  Future<OroSnapshot?> snapshot() => OroBridge(hub).read();
  @override
  Future<String> submit(String orderJson) => hub.oroTradeSubmit(orderJson);
  @override
  Future<String?> result(String id) => hub.oroTradeResult(id);
}

/// A confirmation Friday is waiting on.
class PendingTrade {
  PendingTrade({
    required this.id,
    required this.command,
    required this.targets,
    required this.at,
    required this.messageId,
  });
  final String id;
  final TradeCommand command;

  /// close: exactly the open positions the user saw in the confirmation.
  final List<OroPosition> targets;
  final DateTime at;
  String messageId;

  static const ttl = Duration(minutes: 2);
  bool expired(DateTime now) => now.difference(at) > ttl || now.isBefore(at);

  Map<String, dynamic> orderJson(int nowMs) => command.op == TradeOp.open
      ? {
          'v': 1,
          'id': id,
          'op': 'open',
          'side': command.side,
          'qty': command.oz,
          'lots': command.lots,
          if (command.tp != null) 'tp': command.tp,
          if (command.sl != null) 'sl': command.sl,
          'ts': nowMs,
        }
      : {
          'v': 1,
          'id': id,
          'op': 'close',
          'ids': [for (final p in targets) p.id],
          'ts': nowMs,
        };
}

/// Either a confirmation to show, or a plain answer (error / question).
class TradePlan {
  const TradePlan.confirm(this.text, this.spoken, this.targets) : ready = true;
  const TradePlan.answer(this.text)
      : spoken = null,
        targets = const [],
        ready = false;
  final bool ready;
  final String text;
  final String? spoken;
  final List<OroPosition> targets;
}

enum TradeReply { confirm, cancel, other }

class TradeFlow {
  static const confirmHint = 'Tap Confirm or say "confirm" / "cancel".';

  static String supportAnswer(String support) {
    switch (support) {
      case 'missing':
        return "Sona isn't installed on this phone, so Friday can't place paper trades. Install Sona, open it once and unlock your paper account.";
      case 'unsupported':
        return 'Your Sona app is too old to take trades from Friday. Update Sona (Settings > Check for updates), open it once, then try again.';
      case 'unavailable':
        return 'Trading from Friday works on the phone, where Sona runs.';
      default:
        return "I couldn't reach Sona on this phone. Open Sona once, then try again.";
    }
  }

  /// Builds the confirmation (or the reason there can't be one) from Sona's
  /// own snapshot. Pure; [nowMs] injectable.
  static TradePlan plan(TradeCommand c, OroSnapshot? s, {required int nowMs}) {
    if (s == null) {
      return const TradePlan.answer(
          "I couldn't read Sona's data. Open Sona once on this phone and unlock your paper account, then try again.");
    }
    return c.op == TradeOp.open ? _planOpen(c, s, nowMs) : _planClose(c, s, nowMs);
  }

  static TradePlan _planOpen(TradeCommand c, OroSnapshot s, int nowMs) {
    final buy = c.side == 'buy';
    final px = buy ? s.ask : s.bid;
    if (px != null && px.isFinite && px > 0) {
      final err = protectionError(c.side!, px, c.tp, c.sl);
      if (err != null) {
        return TradePlan.answer(
            '$err Sona\'s last ${buy ? 'ask' : 'bid'} was ${price(px)}. No order sent.');
      }
    }
    final b = StringBuffer()
      ..write('Confirm paper trade: ${buy ? 'BUY' : 'SELL'} ${lotsLabel(c.lots!)} XAU/USD at market.\n');
    if (px == null || !px.isFinite || px <= 0) {
      b.write('Sona has not shared a live price yet; it will refuse the order if it has no fresh quote.\n');
    } else {
      final age = s.quoteAt > 0 ? nowMs - s.quoteAt : null;
      b.write('Last Sona ${buy ? 'ask' : 'bid'}: ${price(px)} (${age == null ? 'age unknown' : ageLabel(age)}).');
      if (age == null || age > 60000) {
        b.write(' That price is not live - Sona fills at its own live price and refuses if it has none.');
      }
      b.write('\n');
    }
    b.write('TP ${c.tp == null ? 'none' : price(c.tp!)} · SL ${c.sl == null ? 'none' : price(c.sl!)}\n');
    b.write('Sona places it with its own checks (market hours, limits, margin). $confirmHint');
    final spoken =
        '${buy ? 'Buy' : 'Sell'} ${lotsSpoken(c.lots!)} of gold${px == null ? '' : ' at about ${px.toStringAsFixed(0)}'}'
        '${c.tp == null ? '' : ', take profit ${c.tp!.toStringAsFixed(0)}'}'
        '${c.sl == null ? '' : ', stop loss ${c.sl!.toStringAsFixed(0)}'}. Say confirm or cancel.';
    return TradePlan.confirm(b.toString(), spoken, const []);
  }

  static TradePlan _planClose(TradeCommand c, OroSnapshot s, int nowMs) {
    if (s.accountKnown != true) {
      return const TradePlan.answer(
          "Sona hasn't synced your paper account yet, so I can't see which trades are open. Open Sona and let it sync, then try again.");
    }
    final accountAge = s.accountAt > 0 ? ageLabel(nowMs - s.accountAt) : 'an unknown time ago';
    final which = c.side == null ? '' : ' ${c.side}';
    final targets = [
      for (final p in s.open)
        if (c.side == null || (p.dir ?? '').toLowerCase() == c.side) p
    ];
    if (targets.isEmpty) {
      return TradePlan.answer('No open$which trades in Sona (account as of $accountAge). Nothing to close.');
    }
    if (!c.all && targets.length > 1) {
      final list = targets.take(4).map((p) => positionLabel(p, s)).join('; ');
      final more = targets.length > 4 ? '; and ${targets.length - 4} more' : '';
      final hint = c.side != null
          ? 'Say "close all ${c.side}s" to close them all, or close one in Sona.'
          : 'Say "close all trades", "close my buy" or "close my sell".';
      return TradePlan.answer(
          'You have ${targets.length} open$which trades: $list$more. Which one? $hint');
    }
    if (targets.any((p) => p.id == null || p.id!.isEmpty)) {
      return const TradePlan.answer(
          'Your Sona app is too old to close trades from Friday. Update Sona (Settings > Check for updates), open it once, then try again.');
    }
    final b = StringBuffer()
      ..write(targets.length == 1
          ? 'Confirm close of 1 paper trade:\n'
          : 'Confirm close of ${targets.length} paper trades:\n');
    for (final p in targets) {
      b.write('• ${positionLabel(p, s)}\n');
    }
    final quoteAge = s.quoteAt > 0 ? ageLabel(nowMs - s.quoteAt) : 'age unknown';
    b.write('P/L uses Sona\'s last quote ($quoteAge, bid ${s.bid == null ? '?' : price(s.bid!)} / ask ${s.ask == null ? '?' : price(s.ask!)}); '
        'Sona closes at its live price. Account as of $accountAge. $confirmHint');
    final spoken = targets.length == 1
        ? 'Close your ${(targets.first.dir ?? '').toLowerCase()} trade of ${ozSpoken(targets.first.qty)}? Say confirm or cancel.'
        : 'Close ${targets.length} trades? Say confirm or cancel.';
    return TradePlan.confirm(b.toString(), spoken, targets);
  }

  /// Same rules as Sona's validateProtection (trade_safety.dart), checked
  /// early against Sona's last quote so an obvious mistake is caught before
  /// the confirmation. Sona re-checks against its live price.
  static String? protectionError(String side, double entry, double? tp, double? sl) {
    for (final v in [tp, sl]) {
      if (v != null && (!v.isFinite || v <= 0)) return 'TP and SL must be positive prices.';
    }
    if (tp != null && (side == 'buy' ? tp <= entry : tp >= entry)) {
      return 'Take profit must be ${side == 'buy' ? 'above' : 'below'} the entry price for a $side.';
    }
    if (sl != null && (side == 'buy' ? sl >= entry : sl <= entry)) {
      return 'Stop loss must be ${side == 'buy' ? 'below' : 'above'} the entry price for a $side.';
    }
    return null;
  }

  static final _yes = RegExp(
      r"^(?:yes|yeah|yep|yup|ya|haan|ha|confirm|confirmed|i confirm|do it|place it|go ahead|go|ok|okay|sure|yes please|yes confirm|confirm it|confirm trade|confirm the trade|close it|yes close it|execute|proceed)$");
  static final _no = RegExp(
      r"^(?:no|nope|nah|cancel|cancel it|cancel that|cancel trade|cancel the trade|stop|don't|dont|do not|abort|never mind|nevermind|forget it|no thanks|leave it)$");

  static TradeReply classifyReply(String text) {
    final t = text
        .toLowerCase()
        .replaceAll(RegExp(r'[.!?,]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceFirst(RegExp(r'^(?:friday )'), '')
        .trim();
    if (_yes.hasMatch(t)) return TradeReply.confirm;
    if (_no.hasMatch(t)) return TradeReply.cancel;
    return TradeReply.other;
  }

  /// Turns Sona's result JSON into Friday's reply.
  static String resultText(String raw, PendingTrade p) {
    Map<String, dynamic> j;
    try {
      j = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return 'Sona answered, but I could not read the result. Open Sona to check the trade.';
    }
    final status = j['status']?.toString() ?? '';
    final message = (j['message']?.toString() ?? '').trim();
    if (status == 'rejected') {
      return 'Sona did not ${p.command.op == TradeOp.open ? 'place the trade' : 'close the trade'}: '
          '${message.isEmpty ? 'no reason given' : message}';
    }
    if (p.command.op == TradeOp.open) {
      final f = j['fill'] is Map ? Map<String, dynamic>.from(j['fill'] as Map) : null;
      if (status == 'done' && f != null) {
        final side = (f['side'] ?? p.command.side).toString().toUpperCase();
        final qty = (f['qty'] as num?)?.toDouble() ?? p.command.oz!;
        final entry = (f['entry'] as num?)?.toDouble();
        final tp = (f['tp'] as num?)?.toDouble();
        final sl = (f['sl'] as num?)?.toDouble();
        return 'Done. Sona opened $side ${lotsLabel(qty / 100)} XAU/USD'
            '${entry == null ? '' : ' at ${price(entry)}'}. '
            'TP ${tp == null ? 'none' : price(tp)} · SL ${sl == null ? 'none' : price(sl)}. Paper trade.';
      }
      if (status == 'done') {
        return 'Done. Sona opened the paper trade${message.isEmpty ? '' : ': $message'}.';
      }
    } else {
      final closed = (j['closed'] as List? ?? const []).whereType<Map>().toList();
      final failed = (j['failed'] as List? ?? const []).whereType<Map>().toList();
      final lines = <String>[];
      for (final c in closed) {
        final side = (c['side'] ?? '').toString().toUpperCase();
        final qty = (c['qty'] as num?)?.toDouble();
        final exit = (c['exit'] as num?)?.toDouble();
        final pnl = (c['pnl'] as num?)?.toDouble();
        lines.add('Closed $side ${qty == null ? '' : '${ozLabel(qty)} '}'
            '${exit == null ? '' : 'at ${price(exit)}'}'
            '${pnl == null ? '' : ', P/L ${signedMoney(pnl)}'}.'.replaceAll('  ', ' '));
      }
      for (final f in failed) {
        final side = (f['side'] ?? '').toString().toUpperCase();
        final qty = (f['qty'] as num?)?.toDouble();
        lines.add('Not closed: $side ${qty == null ? '' : ozLabel(qty)} - ${f['reason'] ?? 'no reason given'}');
      }
      if (lines.isNotEmpty) return lines.join('\n');
      if (status == 'done') return 'Done. Sona closed the trade${message.isEmpty ? '' : ': $message'}.';
    }
    return message.isEmpty
        ? 'Sona answered without a clear result. Open Sona to check the trade.'
        : message;
  }

  static String spokenResult(String text) {
    if (text.startsWith('Done. Sona opened')) return 'Trade placed';
    if (text.startsWith('Closed ') && !text.contains('Not closed')) return 'Trade closed';
    if (text.startsWith('Sona did not')) return "Sona didn't do it. Check the screen";
    return 'Check the screen';
  }

  static String positionLabel(OroPosition p, OroSnapshot s) {
    final dir = (p.dir ?? '').toLowerCase() == 'sell' ? 'SELL' : 'BUY';
    final qty = p.qty == null ? '' : ' ${ozLabel(p.qty!)}';
    final entry = p.entry == null ? '' : ' at ${price(p.entry!)}';
    final marks = [
      if (p.tp != null) 'TP ${price(p.tp!)}',
      if (p.sl != null) 'SL ${price(p.sl!)}',
    ];
    var out = '$dir$qty$entry${marks.isEmpty ? '' : ' (${marks.join(', ')})'}';
    if (p.entry != null && p.qty != null && s.bid != null && s.ask != null) {
      final sell = dir == 'SELL';
      final mark = sell ? s.ask! : s.bid!;
      final pnl = (sell ? p.entry! - mark : mark - p.entry!) * p.qty!;
      if (pnl.isFinite) out += ', ${pnl >= 0 ? 'up' : 'down'} \$${pnl.abs().toStringAsFixed(2)}';
    }
    return out;
  }

  static String lotsLabel(double lots) {
    final oz = (lots * 100).round();
    return '${lots.toStringAsFixed(2)} lot${lots > 0.01 + 1e-9 ? 's' : ''} ($oz oz)';
  }

  static String lotsSpoken(double lots) {
    final s = lots.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
    return '$s lot${lots > 0.01 + 1e-9 ? 's' : ''}';
  }

  static String ozLabel(double oz) {
    final lots = oz / 100;
    final ozTxt = oz == oz.roundToDouble() ? oz.toInt().toString() : oz.toStringAsFixed(2);
    return '${lots.toStringAsFixed(2)} lot ($ozTxt oz)';
  }

  static String ozSpoken(double? oz) {
    if (oz == null) return 'unknown size';
    return lotsSpoken(oz / 100);
  }

  static String ageLabel(int ms) {
    if (ms < 0) return 'just now';
    final sec = ms ~/ 1000;
    if (sec < 10) return 'just now';
    if (sec < 60) return '$sec s old';
    final min = sec ~/ 60;
    if (min < 60) return '$min min old';
    final h = min ~/ 60;
    if (h < 24) return '$h h old';
    return '${h ~/ 24} d old';
  }

  static String price(double v) {
    final s = v.toStringAsFixed(2);
    final parts = s.split('.');
    final d = parts[0];
    final b = StringBuffer();
    for (var i = 0; i < d.length; i++) {
      final fromEnd = d.length - i;
      b.write(d[i]);
      if (fromEnd > 1 && fromEnd % 3 == 1) b.write(',');
    }
    return '$b.${parts[1]}';
  }

  static String signedMoney(double v) =>
      '${v >= 0 ? '+' : '-'}\$${price(v.abs())}';
}

/// Sends a confirmed order and waits for Sona's answer.
class OroTradeExecutor {
  OroTradeExecutor(this.desk,
      {this.timeout = const Duration(seconds: 45),
      this.poll = const Duration(milliseconds: 700),
      int Function()? nowMs})
      : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);
  final OroTradeDesk desk;
  final Duration timeout;
  final Duration poll;
  final int Function() _nowMs;

  Future<String> execute(PendingTrade p) async {
    final sent = await desk.submit(jsonEncode(p.orderJson(_nowMs())));
    if (sent != 'ok') {
      return '${TradeFlow.supportAnswer(sent)} No order was sent.';
    }
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final raw = await desk.result(p.id);
      if (raw != null && raw.isNotEmpty) {
        String? status;
        try {
          status = (jsonDecode(raw) as Map)['status']?.toString();
        } catch (_) {}
        if (status != 'working' && status != 'queued') {
          return TradeFlow.resultText(raw, p);
        }
      }
      await Future<void>.delayed(poll);
    }
    return "Sona did not report back within ${timeout.inSeconds} seconds. Open Sona to check whether the "
        "${p.command.op == TradeOp.open ? 'trade was placed' : 'trade was closed'} - Friday will not send it again.";
  }
}
