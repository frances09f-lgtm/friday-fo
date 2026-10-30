import '../speech/voice_repair.dart';

/// A narrow, on-device task. The command parser never uses a cloud model.
///
/// [direction] is `above`, `below`, `auto` (the user named a target but no
/// direction: "tell me when gold hits 4000" - Friday picks above or below
/// from the latest saved quote) or `cross` (no direction and no quote to
/// compare with - the phone fixes the direction from the first fresh quote
/// it sees, so the alert fires when gold reaches the target either way).
class GoldTaskRequest {
  const GoldTaskRequest(this.direction, this.threshold, this.intervalMinutes);
  final String direction;
  final double threshold;
  final int intervalMinutes;

  static const _asset = r'\b(?:gold|xau(?:\s*/?\s*usd)?)\b';

  static bool isWatchLike(String text) => RegExp(
          r'\b(?:check\w*|watch|monitor)\b.*\d+\s*(?:minutes?|mins?|hours?)\b.*\b(?:tell|notify|alert)\b|\b(?:check|watch|monitor)\b.*\bevery\b.*\b(?:tell|notify|alert)\b|\b(?:gold|xau)\b.*\b(?:above|below)\b.*\d',
          caseSensitive: false)
      .hasMatch(text);

  static bool isAlertRequest(String text) => RegExp(
          r'\b(ping|alert|notify|tell|warn|inform|let me know)\b.*\b(when|if|once|as soon as)\b.*\b(gold|xau)|\b(gold|xau)\b.*\b(alert|notify|ping)\b',
          caseSensitive: false)
      .hasMatch(text);

  /// "alert me when the price goes above 4000" - an alert with a target but
  /// no asset. The one case where Friday has to ask what to watch.
  static bool isAssetlessAlert(String text) {
    final t = text.toLowerCase();
    if (RegExp(_asset).hasMatch(t)) return false;
    return RegExp(
                r'\b(?:ping|alert|notify|tell|warn|let me know)\b.*\b(?:when|if|once|as soon as)\b')
            .hasMatch(t) &&
        RegExp(r'\b(?:price|rate|it)\b').hasMatch(t) &&
        RegExp(r'\b(?:above|abv|over|below|under|hits?|reach(?:es)?|cross(?:es)?|touch(?:es)?|goes|drops?|falls?|rises?)\b')
            .hasMatch(t) &&
        RegExp(r'\d').hasMatch(t) &&
        !RegExp(r'\b(?:battery|volume|brightness|storage|temperature|trade|trades|tp|sl)\b')
            .hasMatch(t);
  }

  // Words that mean "go up to/over the target".
  static final _upWords = RegExp(
      r'(?:>=|≥|>|\bmore than\b|\bgreater than\b|\bhigher than\b|\bbigger than\b|\bexceeds?\b|\bexceeding\b'
      r'|\babove\b|\babv\b|\babov\b|\babobe\b|\babouve\b|\bover\b|\bpast\b|\bbeyond\b|\btops?\b'
      r'|\bbreaks? above\b|\bcross(?:es|ed)? above\b|\bcross(?:es|ed)? over\b'
      r'|\b(?:goes|go|going|gets|moves|climbs?|rises?|rising|jumps?|shoots?|runs?|pumps?|spikes?) up\b'
      r'|\b(?:rises?|rising|rose|climbs?|climbing|jumps?|jumping|rallies|rally|surges?|spikes?|soars?)\b'
      r'|\b(?:goes|go|going|gets|moves|trades?|trading|climbs?) about\b|\babout for\b)');

  // Words that mean "go down to/under the target".
  static final _downWords = RegExp(
      r'(?:<=|≤|<|\bless than\b|\blower than\b|\bsmaller than\b|\bcheaper than\b'
      r'|\bbelow\b|\bbelo\b|\bblow\b|\bunder\b|\bbeneath\b'
      r'|\bbreaks? below\b|\bcross(?:es|ed)? below\b|\bcross(?:es|ed)? under\b'
      r'|\b(?:goes|go|going|gets|moves|comes?|coming) down\b|\bdown to\b'
      r'|\b(?:drops?|dropping|dropped|falls?|falling|fell|dips?|dipping|sinks?|sinking|slides?|sliding|slips?|crash(?:es)?|tanks?|declines?|plunges?|plummets?)\b)');

  static final _tradeWords = RegExp(
      r'\b(?:buy|sell|long|short|lots?|positions?|my trades?|tp|sl|take profit|stop loss|orders?)\b');

  // An alert asks to be told later. "check if gold is above 4000" or
  // "when was gold above 4000" are questions about now, not alerts.
  static final _intent = RegExp(
      r'\b(?:ping|alert|alerts|notify|notification|tell|warn|inform|let me know|message me|remind|watch|monitor|track|buzz|ring)\b|\b(?:whenever|once|as soon as)\b|\bwhen\b(?!\s+(?:was|did|were|has|had|is the)\b)');

  /// Reads a gold alert in any everyday phrasing, including the words a
  /// speech recognizer commonly gets wrong ("goes about 4000"). Returns null
  /// when the text is not a gold alert Friday can act on without asking.
  static GoldTaskRequest? parse(String text) {
    final r = read(text);
    return r != null && r.certain ? r.request : null;
  }

  /// Like [parse], but also returns a best guess Friday should confirm
  /// first ([GoldAlertReading.certain] false): sound-alike words, or an
  /// interval the phone cannot run.
  static GoldAlertReading? read(String text) {
    final numbered = VoiceRepair.numbers(text);
    final (fixed, fixes) = VoiceRepair.known(numbered);
    final exact = _core(fixed);
    if (exact != null) return GoldAlertReading(exact, true, fixes);
    final fuzzy = VoiceRepair.fuzzy(fixed);
    if (fuzzy != null) {
      final guess = _core(fuzzy.$1) ?? _core(fuzzy.$1, clampInterval: true);
      if (guess != null) {
        return GoldAlertReading(guess, false, [...fixes, ...fuzzy.$2]);
      }
    }
    final clamped = _core(fixed, clampInterval: true);
    if (clamped != null) {
      return GoldAlertReading(clamped, false, [...fixes, 'interval']);
    }
    return null;
  }

  static GoldTaskRequest? _core(String text, {bool clampInterval = false}) {
    var t = ' ${text.trim().toLowerCase()} ';
    if (!RegExp(_asset).hasMatch(t)) return null;
    if (!_intent.hasMatch(t)) return null;
    if (_tradeWords.hasMatch(t)) return null;

    // Interval: "every 10 minutes", "every hour", "every 2 hrs".
    var minutes = 5;
    final every = RegExp(
            r'\bevery\s+(?:(\d+(?:\.\d+)?)\s*(minutes?|mins?|m|hours?|hrs?|h)\b|(hour|minute)\b)')
        .firstMatch(t);
    if (every != null) {
      if (every[3] != null) {
        minutes = every[3] == 'hour' ? 60 : 1;
      } else {
        final n = double.parse(every[1]!);
        minutes = (every[2]!.startsWith('h') ? n * 60 : n).round();
      }
      t = t.replaceRange(every.start, every.end, ' ');
    }
    if (minutes < 5 || minutes > 1440) {
      if (!clampInterval) return null;
      minutes = minutes.clamp(5, 1440);
    }

    // Money and number clean-up: ₹4,000 / $4000 / 4k / 4.1k / usd 4000.
    t = t.replaceAll(RegExp(r'(?<=\d),(?=\d{2,3}\b)'), '').replaceAll(
        RegExp(r'[₹$]|\b(?:rs\.?|inr|usd|dollars?|rupees?)(?=\s|\d|$)'), ' ');
    t = t.replaceAllMapped(RegExp(r'(\d+(?:\.\d+)?)\s*k\b'),
        (m) => (double.parse(m[1]!) * 1000).toString());

    final numbers = RegExp(r'(?<![\w.])(\d+(?:\.\d+)?)(?!\w)')
        .allMatches(t)
        .where((m) => !RegExp(
                r'^\s*(?:minutes?|mins?|hours?|hrs?|seconds?|secs?|%|percent|am|pm)\b')
            .hasMatch(t.substring(m.end)))
        .toList();
    if (numbers.isEmpty) return null;
    final target = numbers.last;
    final threshold = double.tryParse(target[1]!);
    if (threshold == null || !threshold.isFinite || threshold <= 0) return null;

    // The direction word that sits closest before the target wins
    // ("below 4000" in "if gold drops ... below 4000"); otherwise none.
    final before = t.substring(0, target.start);
    final up = _upWords
        .allMatches(before)
        .map((m) => m.end)
        .fold<int>(-1, (a, b) => b > a ? b : a);
    final down = _downWords
        .allMatches(before)
        .map((m) => m.end)
        .fold<int>(-1, (a, b) => b > a ? b : a);
    final direction =
        up < 0 && down < 0 ? 'auto' : (up > down ? 'above' : 'below');
    return GoldTaskRequest(direction, threshold, minutes);
  }

  /// Picks the direction for an `auto` request from the latest saved quote:
  /// a target above the current price waits for gold to rise to it, a target
  /// below waits for it to fall. With no usable quote the phone watches for
  /// a cross either way.
  GoldTaskRequest resolve(double? currentPrice) {
    if (direction != 'auto') return this;
    if (currentPrice == null ||
        !currentPrice.isFinite ||
        currentPrice <= 0 ||
        currentPrice == threshold) {
      return GoldTaskRequest('cross', threshold, intervalMinutes);
    }
    return GoldTaskRequest(threshold > currentPrice ? 'above' : 'below',
        threshold, intervalMinutes);
  }

  /// The command Friday would run for this request, in words [parse] reads
  /// back exactly: "alert me when gold goes above 4000".
  String get canonical {
    final n = formatPrice(threshold).replaceAll(',', '');
    final what = direction == 'above' || direction == 'below'
        ? 'goes $direction $n'
        : 'reaches $n';
    final every = intervalMinutes == 5
        ? ''
        : intervalMinutes % 60 == 0
            ? (intervalMinutes == 60
                ? ' every hour'
                : ' every ${intervalMinutes ~/ 60} hours')
            : ' every $intervalMinutes minutes';
    return 'alert me when gold $what$every';
  }

  /// "alert when gold goes above 4,000" - the readable form for a
  /// "Did you mean" question.
  String get readable {
    final n = formatPrice(threshold);
    final what = direction == 'above' || direction == 'below'
        ? 'goes $direction $n'
        : 'reaches $n';
    final every = intervalMinutes == 5
        ? ''
        : intervalMinutes % 60 == 0
            ? ', checking every ${intervalMinutes ~/ 60 == 1 ? 'hour' : '${intervalMinutes ~/ 60} hours'}'
            : ', checking every $intervalMinutes min';
    return 'alert when gold $what$every';
  }

  /// The price to compare a target with: Sona's saved mid (or the one side
  /// it has) when that quote is under [maxAge] old. Null otherwise.
  static double? usableQuote(double? bid, double? ask, int quoteAt, int nowMs,
      {Duration maxAge = const Duration(hours: 12)}) {
    if (quoteAt <= 0 || quoteAt > nowMs + 60000) return null;
    if (nowMs - quoteAt > maxAge.inMilliseconds) return null;
    bool ok(double? v) => v != null && v.isFinite && v > 0;
    if (ok(bid) && ok(ask) && ask! >= bid!) return (bid + ask) / 2;
    if (ok(bid)) return bid;
    if (ok(ask)) return ask;
    return null;
  }

  /// The chat reply once the phone answered a create: the short
  /// confirmation when it saved the task, its own words when it did not.
  String createdReply(String nativeReply, {double? currentPrice}) {
    if (!nativeReply.startsWith('Saved')) return nativeReply;
    var reply = confirmation(currentPrice: currentPrice);
    if (currentPrice != null) {
      if (direction == 'above' && currentPrice > threshold) {
        reply += ' Gold is already above that, so it fires on the next check.';
      } else if (direction == 'below' && currentPrice < threshold) {
        reply += ' Gold is already below that, so it fires on the next check.';
      }
    }
    if (nativeReply.contains('Battery saver')) {
      reply += ' Battery saver is on, so checks can be 15+ min apart.';
    }
    return reply;
  }

  /// "Alert set: gold above 4,000 (now 3,962). Checking every 5 min."
  String confirmation({double? currentPrice}) {
    final now =
        currentPrice != null && currentPrice.isFinite && currentPrice > 0
            ? ' (now ${formatPrice(currentPrice.roundToDouble())})'
            : '';
    final what = direction == 'cross' || direction == 'auto'
        ? 'gold reaches ${formatPrice(threshold)}'
        : 'gold $direction ${formatPrice(threshold)}';
    final every = intervalMinutes % 60 == 0
        ? (intervalMinutes == 60
            ? 'every hour'
            : 'every ${intervalMinutes ~/ 60} hours')
        : 'every $intervalMinutes min';
    final extra = direction == 'cross'
        ? ' No saved quote yet, so it fires when gold reaches it from either side.'
        : '';
    return 'Alert set: $what$now. Checking $every.$extra';
  }

  /// 4000 -> "4,000"; 3962.45 -> "3,962.45".
  static String formatPrice(double v) {
    final whole = v == v.roundToDouble();
    final s = whole ? v.round().toString() : v.toStringAsFixed(2);
    final parts = s.split('.');
    final digits = parts[0];
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
      buf.write(digits[i]);
    }
    return parts.length > 1 ? '$buf.${parts[1]}' : buf.toString();
  }

  Map<String, dynamic> toJson() => {
        'direction': direction,
        'threshold': threshold,
        'intervalMinutes': intervalMinutes,
      };
}

/// What Friday read from an alert sentence. [certain] is false when the
/// reading needed a sound-alike guess or a changed interval; Friday then
/// asks "Did you mean ...?" instead of creating the alert.
class GoldAlertReading {
  const GoldAlertReading(this.request, this.certain, this.fixes);
  final GoldTaskRequest request;
  final bool certain;

  /// Each repair made to the heard words, e.g. "about -> above".
  final List<String> fixes;
}

/// A gold alert waiting for the user's Yes after "Did you mean ...?".
class PendingAlert {
  const PendingAlert(this.messageId, this.request);
  final String messageId;
  final GoldTaskRequest request;

  static bool isYes(String text) => RegExp(
          r'^\s*(?:yes|yeah|yah|yep|yup|ya|yes please|haan|han|ha|haa|ji|ok|okay|sure|correct|right|do it|confirm|set it|go ahead)\s*[.!]*\s*$',
          caseSensitive: false)
      .hasMatch(text);

  static bool isNo(String text) => RegExp(
          r'^\s*(?:no|nope|nah|na|nahi|cancel|wrong|leave it|don.?t)\s*[.!]*\s*$',
          caseSensitive: false)
      .hasMatch(text);
}
