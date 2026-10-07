import 'dart:convert';

import '../device/device_hub.dart';

/// One open Oro paper position as exposed by the offline bridge.
class OroPosition {
  const OroPosition({this.dir, this.qty, this.entry, this.tp, this.sl});

  final String? dir; // 'buy' / 'sell'
  final double? qty;
  final double? entry;
  final double? tp;
  final double? sl;
}

/// The real snapshot Oro publishes on the phone: latest quote it actually
/// saw, the paper balance, and open positions. Every number came from
/// Oro's own live data - the quote timestamp travels along so answers can
/// say how old they are instead of pretending to be live.
class OroSnapshot {
  const OroSnapshot({
    required this.ts,
    this.bid,
    this.ask,
    this.quoteAt = 0,
    this.balance,
    this.accountAt = 0,
    this.accountKnown,
    this.open = const [],
  });

  final int ts; // when the snapshot was written
  final double? bid;
  final double? ask;
  final int quoteAt; // when the quote was actually fetched
  final double? balance;
  final int accountAt;
  final bool? accountKnown;
  final List<OroPosition> open;

  static OroSnapshot? parse(String raw) {
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return OroSnapshot(
        ts: (j['ts'] as num?)?.toInt() ?? 0,
        bid: (j['bid'] as num?)?.toDouble(),
        ask: (j['ask'] as num?)?.toDouble(),
        quoteAt: (j['quoteAt'] as num?)?.toInt() ?? 0,
        balance: (j['balance'] as num?)?.toDouble(),
        accountAt: (j['accountAt'] as num?)?.toInt() ?? 0,
        accountKnown:
            j['accountKnown'] is bool ? j['accountKnown'] as bool : null,
        open: [
          for (final p in (j['open'] as List? ?? const []))
            if (p is Map)
              OroPosition(
                dir: p['dir']?.toString(),
                qty: (p['qty'] as num?)?.toDouble(),
                entry: (p['entry'] as num?)?.toDouble(),
                tp: (p['tp'] as num?)?.toDouble(),
                sl: (p['sl'] as num?)?.toDouble(),
              ),
        ],
      );
    } catch (_) {
      return null;
    }
  }
}

/// Reads Oro's on-device snapshot and builds spoken answers from it.
/// Phone-only by design (user: the connection must work offline); the
/// router keeps the laptop on an honest "phone only" line.
class OroBridge {
  OroBridge(this.hub);

  final DeviceHub hub;

  Future<OroSnapshot?> read() async {
    final raw = await hub.oroStatusRaw();
    if (raw == null || raw.isEmpty) return null;
    return OroSnapshot.parse(raw);
  }

  /// Builds the answer for one query kind ('price', 'trades', 'tpsl',
  /// 'balance') from a snapshot. Pure and testable; [nowMs] injectable.
  static String answer(String kind, OroSnapshot? s, {int? nowMs}) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    if (s == null) {
      return "I couldn't read Oro's data - open Oro once on this phone so it can share its latest numbers.";
    }
    final quoteAge = s.quoteAt > 0 ? _age(now - s.quoteAt) : 'an unknown time';
    final accountAge =
        s.accountAt > 0 ? _age(now - s.accountAt) : 'an unknown time';
    if (kind != 'price' && s.accountKnown == false) {
      return "Oro has not synced account data yet. I cannot tell whether there are open trades. Open Oro and let it sync.";
    }
    switch (kind) {
      case 'price':
        if (s.bid == null || s.ask == null) {
          return "Oro hasn't seen a live gold price yet - open Oro and let it connect once.";
        }
        final mid = (s.bid! + s.ask!) / 2;
        return 'Gold is at ${_price(mid)}, as of $quoteAge.';
      case 'trades':
        if (s.open.isEmpty)
          return 'No open trades right now, as of $accountAge.';
        final parts = [
          for (final p in s.open.take(3)) _describePosition(p, s),
        ];
        final more = s.open.length > 3 ? ' and ${s.open.length - 3} more' : '';
        return '${s.open.length} open trade${s.open.length == 1 ? '' : 's'}: '
            '${parts.join('; ')}$more. As of $accountAge.';
      case 'tpsl':
        if (s.open.isEmpty) {
          return 'No open trade in the account snapshot, as of $accountAge, so there is no TP or SL set.';
        }
        final p = s.open.first;
        final bits = <String>[
          if (p.tp != null) 'TP ${_price(p.tp!)}',
          if (p.sl != null) 'SL ${_price(p.sl!)}',
        ];
        final what = _posName(p);
        if (bits.isEmpty) return 'Your open $what has no TP or SL set.';
        return 'Your open $what has ${bits.join(' and ')}. As of $accountAge.';
      case 'balance':
        if (s.balance == null) {
          return "Oro hasn't synced the paper balance yet - open it once.";
        }
        return 'Your paper balance is \$${_money(s.balance!)}, as of $accountAge.';
      default:
        return answer('price', s, nowMs: now);
    }
  }

  static String _posName(OroPosition p) {
    final dir = (p.dir ?? '').toLowerCase() == 'sell' ? 'sell' : 'buy';
    final qty = p.qty == null ? '' : ' ${_qty(p.qty!)} oz';
    final entry = p.entry == null ? '' : ' at ${_price(p.entry!)}';
    return '$dir$qty$entry';
  }

  static String _describePosition(OroPosition p, OroSnapshot s) {
    var d = _posName(p);
    final marks = <String>[
      if (p.tp != null) 'TP ${_price(p.tp!)}',
      if (p.sl != null) 'SL ${_price(p.sl!)}',
    ];
    if (marks.isNotEmpty) d += ' (${marks.join(', ')})';
    final pnl = _floating(p, s);
    if (pnl != null) {
      d += pnl >= 0 ? ', up \$${_money(pnl)}' : ', down \$${_money(-pnl)}';
    }
    return d;
  }

  /// Floating P/L from the real quote and entry - never invented.
  static double? _floating(OroPosition p, OroSnapshot s) {
    if (p.entry == null || p.qty == null) return null;
    if (s.bid == null || s.ask == null) return null;
    final isSell = (p.dir ?? '').toLowerCase() == 'sell';
    final mark = isSell ? s.ask! : s.bid!;
    return (isSell ? p.entry! - mark : mark - p.entry!) * p.qty!;
  }

  static String _age(int diffMs) {
    if (diffMs < 0) return 'just now';
    final sec = diffMs ~/ 1000;
    if (sec < 45) return 'just now';
    final min = sec ~/ 60;
    if (min < 1) return 'a minute ago';
    if (min == 1) return 'a minute ago';
    if (min < 60) return '$min minutes ago';
    final h = min ~/ 60;
    if (h < 24) return h == 1 ? 'an hour ago' : '$h hours ago';
    final d = h ~/ 24;
    return d == 1 ? 'a day ago' : '$d days ago';
  }

  static String _price(double v) {
    final s = v.toStringAsFixed(1);
    final parts = s.split('.');
    return '${_group(parts[0])}.${parts[1]}';
  }

  static String _money(double v) {
    final neg = v < 0;
    final s = v.abs().toStringAsFixed(2);
    final parts = s.split('.');
    return '${neg ? '-' : ''}${_group(parts[0])}.${parts[1]}';
  }

  static String _qty(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    final s = v.toStringAsFixed(2);
    return s.endsWith('0') ? s.substring(0, s.length - 1) : s;
  }

  static String _group(String digits) {
    final b = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      final fromEnd = digits.length - i;
      b.write(digits[i]);
      if (fromEnd > 1 && fromEnd % 3 == 1) b.write(',');
    }
    return b.toString();
  }
}
