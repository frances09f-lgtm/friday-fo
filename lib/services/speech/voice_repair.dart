/// Repairs the words a speech recognizer most often gets wrong in Friday's
/// alert commands, without a cloud model.
///
/// Two strengths of repair:
/// * [known] - mishearings seen in real use ("goes about 4000" for "goes
///   above 4000", "blow" for "below", "goal" for "gold"). Each fix only
///   fires in its slot (a direction word right before the target number,
///   the asset word in an alert), so it cannot turn some other sentence
///   into a command. Friday acts on these directly.
/// * [fuzzy] - edit-distance and sound-alike matches against a small
///   whitelist per slot. Plausible but not certain, so Friday asks
///   "Did you mean ...?" instead of acting.
class VoiceRepair {
  const VoiceRepair._();

  /// Words that can stand between a direction word and the number:
  /// "above for 4000", "below rs 3950", "over the 4k mark".
  static const filler =
      r'(?:\s+(?:for|of|the|to|at|around|about|near|nearly|approx(?:imately)?|like|rs\.?|inr|usd|₹|\$|dollars?|rupees?|mark|level))*\s*[₹$]?\s*';

  static const _ones = {
    'zero': 0,
    'one': 1,
    'two': 2,
    'three': 3,
    'four': 4,
    'five': 5,
    'six': 6,
    'seven': 7,
    'eight': 8,
    'nine': 9,
    'ten': 10,
    'eleven': 11,
    'twelve': 12,
    'thirteen': 13,
    'fourteen': 14,
    'fifteen': 15,
    'sixteen': 16,
    'seventeen': 17,
    'eighteen': 18,
    'nineteen': 19,
    'twenty': 20,
    'thirty': 30,
    'forty': 40,
    'fourty': 40,
    'fifty': 50,
    'sixty': 60,
    'seventy': 70,
    'eighty': 80,
    'ninety': 90,
  };
  static const _scales = {
    'hundred': 100,
    'thousand': 1000,
    'k': 1000,
    'lakh': 100000,
    'lakhs': 100000,
    'lac': 100000,
  };

  /// "four thousand one hundred twenty" -> "4120", "forty one hundred" ->
  /// "4100", "for thousand" -> "4000", "4 thousand" -> "4000",
  /// "4 000" -> "4000", "4,000" / "1,00,000" -> plain digits, "4k" -> "4000",
  /// "half an hour" -> "30 minutes".
  static String numbers(String text) {
    var t = text
        .replaceAll(RegExp(r'\bhalf (?:an )?hour\b', caseSensitive: false),
            '30 minutes')
        .replaceAll(RegExp(r'(?<=\d),(?=\d{2,3}\b)'), '');
    t = t.replaceAllMapped(
        RegExp(r'\b(\d{1,3}) (000)\b'), (m) => '${m[1]}${m[2]}');
    // "for/to thousand" is "four/two thousand" said fast.
    t = t.replaceAllMapped(
        RegExp(r'\b(for|fore|to|too)\s+(thousand|hundred)\b',
            caseSensitive: false),
        (m) =>
            '${m[1]!.toLowerCase().startsWith('f') ? 'four' : 'two'} ${m[2]}');
    final word = RegExp(r'[A-Za-z]+|\d+(?:\.\d+)?');
    final tokens = word.allMatches(t).toList();
    final out = StringBuffer();
    var last = 0;
    var i = 0;
    while (i < tokens.length) {
      final start = i;
      double total = 0, current = 0;
      var used = 0, words = 0;
      var j = i;
      while (j < tokens.length) {
        final w = tokens[j][0]!.toLowerCase();
        // Only spaces (or "and") may sit between parts of one number.
        if (j > start) {
          final gap = t.substring(tokens[j - 1].end, tokens[j].start);
          if (gap.trim().isNotEmpty) break;
        }
        final digit = double.tryParse(w);
        final n = digit ?? _ones[w]?.toDouble();
        if (n != null) {
          final fits = current == 0 ||
              (current % 100 == 0 && n < 100) ||
              (current % 10 == 0 && current % 100 != 0 && n < 10);
          if (!fits) break;
          current += n;
          if (digit == null) words++;
        } else if (_scales.containsKey(w) && used > 0) {
          final s = _scales[w]!;
          if (s == 100) {
            current = (current == 0 ? 1 : current) * 100;
          } else {
            total += (current == 0 ? 1 : current) * s;
            current = 0;
          }
          words++;
        } else if (w == 'and' &&
            used > 0 &&
            j + 1 < tokens.length &&
            (_ones.containsKey(tokens[j + 1][0]!.toLowerCase()) ||
                double.tryParse(tokens[j + 1][0]!) != null)) {
          // "four thousand and fifty"
        } else {
          break;
        }
        used++;
        j++;
      }
      if (used == 0) {
        i++;
        continue;
      }
      // Leave a lone digit run alone; convert anything with a number word.
      if (words > 0) {
        final value = total + current;
        out.write(t.substring(last, tokens[start].start));
        out.write(value == value.roundToDouble()
            ? value.round().toString()
            : value.toString());
        last = tokens[j - 1].end;
      }
      i = j;
    }
    out.write(t.substring(last));
    return out.toString();
  }

  // --- known mishearings -------------------------------------------------

  static final _aboveHeard = [
    'about',
    'abaut',
    'abut',
    'abot',
    'abou',
    'abov',
    'abow',
    'abowe',
    'abuv',
    'abuve',
    'abve',
    'abv',
    'abbove',
    'abav',
    'abave',
    'aboove',
    'abobe',
    'abouve',
    'ebove',
    'abhove',
    'ubove',
    'a bove',
    'a bow',
    'a bov',
    'a buv',
    'a bob',
    'a both',
    'ab of',
    'a boat',
    'a bough',
    'uh bove',
    'ever',
    'avove',
    'abode',
    'aboard',
  ];
  static final _belowHeard = [
    'blow',
    'blew',
    'bilo',
    'belo',
    'bello',
    'bellow',
    'billow',
    'bilow',
    'bellow',
    'belove',
    'be low',
    'b low',
    'by low',
    'bee low',
    'pillow',
    'below',
  ];
  static final _goldHeard = [
    'goal',
    'goals',
    'gol',
    'goald',
    'gould',
    'golds',
    "gold's",
    'gole',
    'goled',
    'gold rate',
    'gold price',
    'goldprice',
    'xau usd',
    'xauusd',
    'xau',
    'sona price',
  ];

  static String _alt(List<String> words) => words
      .map((w) =>
          RegExp.escape(w).replaceAll(r'\ ', r'\s+').replaceAll(' ', r'\s+'))
      .join('|');

  /// Applies the known fixes. Returns the repaired text and a description
  /// of each fix ("about -> above").
  static (String, List<String>) known(String text) {
    final fixes = <String>[];
    var t = ' ${text.toLowerCase()} ';
    String fix(RegExp re, String to) => t.replaceAllMapped(re, (m) {
          final heard = m[1]!.trim();
          if (heard != to) fixes.add('$heard -> $to');
          return to; // Every pattern below is just the heard word(s).
        });
    // Direction words, only when the target number follows.
    t = fix(RegExp('\\b(${_alt(_aboveHeard)})(?=$filler\\d)'), 'above');
    // "every 4000" with no time unit is "above 4000".
    t = fix(
        RegExp(
            r'\b(every)(?=\s+\d{3,}(?:\.\d+)?(?!\s*(?:minutes?|mins?|m|hours?|hrs?|h|seconds?|secs?)\b))'),
        'above');
    t = fix(RegExp('\\b(${_alt(_belowHeard)})(?=$filler\\d)'), 'below');
    // Asset word, only in an alert-shaped sentence.
    if (!RegExp(r'\bgold\b').hasMatch(t) && _alertShaped(t)) {
      t = fix(RegExp('\\b(${_alt(_goldHeard)})\\b'), 'gold');
    }
    // Alert verbs.
    t = fix(
        RegExp(r'\b(a\s*lot|allert|a\s*lert|alart|a\s*lot\s*of)(?=\s+me\b)'),
        'alert');
    t = fix(
        RegExp(r'\b(tel|tal|till)(?=\s+me\s+(?:when|if|once|as soon as)\b)'),
        'tell');
    t = fix(RegExp(r'\b(notifi|notifie|noti\s*fy|not\s+if\s+i)(?=\s+me\b)'),
        'notify');
    return (t.trim().replaceAll(RegExp(r'\s+'), ' '), fixes);
  }

  static bool _alertShaped(String t) =>
      RegExp(r'\b(?:alert|notify|tell|ping|remind|warn|let me know|watch|monitor|when|whenever|once|as soon as)\b')
          .hasMatch(t) &&
      RegExp(r'\d').hasMatch(t);

  // --- fuzzy ---------------------------------------------------------------

  static const _neutral = {
    'is',
    'at',
    'to',
    'the',
    'for',
    'of',
    'goes',
    'go',
    'hits',
    'hit',
    'reaches',
    'reach',
    'touches',
    'touch',
    'crosses',
    'cross',
    'becomes',
    'comes',
    'near',
    'around',
    'price',
    'rate',
    'gold',
    'me',
    'when',
    'if',
    'and',
    'it',
    'rs',
    'inr',
    'usd',
    'gets',
    'get',
    'every',
    'minutes',
    'hours',
    'on',
    'in',
    'a',
    'an',
    'be',
    'by',
    'up',
    'down',
    'over',
    'under',
    'more',
    'less',
    'than',
    'drops',
    'falls',
    'rises',
    'tell',
    'alert',
    'notify',
    'once',
    'then',
    'there',
    'their',
    'this',
    'that',
    'its',
    'about',
    'above',
    'below',
    'mark',
    'level',
    'like',
    'just',
    'still',
  };

  /// Edit distance (Levenshtein).
  static int distance(String a, String b) {
    if (a == b) return 0;
    var prev = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final cur = List<int>.filled(b.length + 1, 0);
      cur[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        cur[j] = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost]
            .reduce((x, y) => x < y ? x : y);
      }
      prev = cur;
    }
    return prev[b.length];
  }

  /// American Soundex: "above" and "abuv" both give A110.
  static String soundex(String word) {
    final w = word.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    if (w.isEmpty) return '';
    const codes = {
      'b': '1',
      'f': '1',
      'p': '1',
      'v': '1',
      'c': '2',
      'g': '2',
      'j': '2',
      'k': '2',
      'q': '2',
      's': '2',
      'x': '2',
      'z': '2',
      'd': '3',
      't': '3',
      'l': '4',
      'm': '5',
      'n': '5',
      'r': '6',
    };
    final out = StringBuffer(w[0].toUpperCase());
    var last = codes[w[0]] ?? '';
    for (var i = 1; i < w.length && out.length < 4; i++) {
      final ch = w[i];
      final c = codes[ch] ?? '';
      if (c.isNotEmpty && c != last) out.write(c);
      if (ch != 'h' && ch != 'w') last = c;
    }
    return out.toString().padRight(4, '0');
  }

  static bool _close(String heard, String target, int maxEdits) {
    if (heard.length < 3) return false;
    if (distance(heard, target) <= maxEdits) return true;
    return soundex(heard) == soundex(target) &&
        distance(heard, target) <= maxEdits + 1;
  }

  /// Sound-alike repairs for the direction slot (the word right before the
  /// number) and the asset slot. Returns null when nothing was changed.
  static (String, List<String>)? fuzzy(String text) {
    final fixes = <String>[];
    var t = ' ${text.toLowerCase()} ';
    // Direction slot.
    t = t.replaceAllMapped(RegExp('\\b([a-z]+(?:\\s+[a-z]+)?)(?=$filler\\d)'),
        (m) {
      final heard = m[1]!;
      final parts = heard.split(RegExp(r'\s+'));
      // Try the last word alone first, then the two words joined
      // ("a bev" -> "abev").
      for (final cand in [parts.last, parts.join()]) {
        if (_neutral.contains(cand)) continue;
        for (final target in ['above', 'below']) {
          if (_close(cand, target, 2)) {
            fixes.add('$cand -> $target');
            final keep = cand == parts.last && parts.length > 1
                ? '${parts.sublist(0, parts.length - 1).join(' ')} '
                : '';
            return '$keep$target';
          }
        }
      }
      return heard;
    });
    // Asset slot - never when another asset is named.
    if (!RegExp(r'\bgold\b').hasMatch(t) &&
        _alertShaped(t) &&
        !RegExp(r'\b(?:silver|btc|bitcoin|eth|ethereum|crypto|nifty|sensex|banknifty|oil|crude|stock|stocks|share|shares|petrol|diesel|iphone|phone|battery)\b')
            .hasMatch(t)) {
      var done = false;
      t = t.replaceAllMapped(RegExp(r'\b([a-z]{3,6})\b'), (m) {
        final w = m[1]!;
        if (done || _neutral.contains(w)) return w;
        if (const {
              'cold',
              'old',
              'god',
              'golf',
              'gild',
              'guild',
              'gaul',
              'gaud',
              'good',
              'goat',
              'gloat',
              'gored',
              'cord'
            }.contains(w) ||
            _close(w, 'gold', 1)) {
          done = true;
          fixes.add('$w -> gold');
          return 'gold';
        }
        return w;
      });
    }
    if (fixes.isEmpty) return null;
    return (t.trim().replaceAll(RegExp(r'\s+'), ' '), fixes);
  }
}
