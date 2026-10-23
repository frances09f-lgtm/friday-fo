import '../models/friday_response.dart';
import 'tasks/gold_task.dart';

/// Reads "remind me to X at <time>" and "remind me to X in N minutes" with
/// plain code. No model, no network. The Friday chat and the floating
/// assistant bar both go through this before any model is asked.
class ReminderRequest {
  const ReminderRequest._({
    required this.task,
    required this.when,
    required this.relative,
    required this.afterMinutes,
    required this.error,
  });

  factory ReminderRequest.ok({
    required String task,
    required DateTime when,
    required bool relative,
    required int afterMinutes,
  }) =>
      ReminderRequest._(
        task: task,
        when: when,
        relative: relative,
        afterMinutes: afterMinutes,
        error: null,
      );

  factory ReminderRequest.fail(String error) => ReminderRequest._(
        task: '',
        when: null,
        relative: false,
        afterMinutes: 0,
        error: error,
      );

  final String task;
  final DateTime? when;
  final bool relative;
  final int afterMinutes;
  final String? error;

  bool get ok => error == null;

  /// The action the router runs. Absolute times carry the exact local time in
  /// [FridayAction.target]; relative ones carry only the minutes.
  FridayAction toAction() => FridayAction(
        type: FridayActionType.setReminder,
        title: task,
        afterMinutes: afterMinutes,
        target: relative ? '' : (when?.toIso8601String() ?? ''),
      );
}

class ReminderParser {
  const ReminderParser._();

  static const noTimeMessage =
      'I could not read a time in that, so no reminder was saved. Say it like "remind me to drink water at 9:42 pm" or "remind me to drink water in 10 minutes".';
  static const noTaskMessage =
      'I could not tell what to remind you about, so no reminder was saved. Say it like "remind me to drink water at 9:42 pm".';
  static const badTimeMessage =
      'Use a valid time, like 1:03 am or 13:03. No reminder was saved.';
  static const badAmPmMessage =
      'Use 1 to 12 with am or pm. No reminder was saved.';
  static const tooFarMessage =
      'For a reminder more than 7 days away, give a clock time instead. No reminder was saved.';
  static const passedTodayMessage =
      'That time has already passed today, so no reminder was saved.';

  static final _lead = RegExp(
    r'^\s*(?:(?:ok(?:ay)?|hey)[\s,]+)?(?:friday[\s,]+)?(?:please[\s,]+)?'
    r'(?:(?:set|create|add|make)\s+(?:me\s+)?(?:a\s+)?reminder(?:\s+(?:to|for|that))?'
    r'|remind(?:\s+me\b(?:\s+to\b)?|\s+to\b))'
    r'(?:\s+(?<rest>.+?))?[\s.!?]*$',
    caseSensitive: false,
  );

  static const _clock =
      r'(?<d>\d{1,4})(?:\s*[:.]\s*(?<m>\d{2}))?\s*(?<ap>[ap]\.?m\.?)?(?![\d:])';
  static const _within =
      r'(?:in|after)\s+(?<n>\d+|an?|half\s+an?)\s*(?<u>hours?|hrs?|minutes?|mins?)(?![a-z])';

  static final _trailingAt = RegExp(r'^(?<task>.+)\s+at\s+' + _clock + r'$',
      caseSensitive: false);
  static final _leadingAt = RegExp(r'^at\s+' + _clock + r'\s+(?:to\s+)?(?<task>.+)$',
      caseSensitive: false);
  static final _trailingIn =
      RegExp(r'^(?<task>.+)\s+' + _within + r'$', caseSensitive: false);
  static final _leadingIn = RegExp(r'^' + _within + r'\s+(?:to\s+)?(?<task>.+)$',
      caseSensitive: false);

  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];

  /// "Fri 23 Oct, 9:42 PM" - weekday and date included so a 12-hour time is
  /// never ambiguous.
  static String describe(DateTime t) {
    final h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final ap = t.hour < 12 ? 'AM' : 'PM';
    final mm = t.minute.toString().padLeft(2, '0');
    return '${_days[t.weekday - 1]} ${t.day} ${_months[t.month - 1]}, $h12:$mm $ap';
  }

  /// Same as [parse], but leaves gold watches and gold alerts to their own
  /// handlers instead of answering them with a reminder error.
  static ReminderRequest? parseForChat(String text, DateTime now) {
    if (GoldTaskRequest.parse(text) != null) return null;
    final r = parse(text, now);
    if (r == null) return null;
    if (!r.ok &&
        (GoldTaskRequest.isWatchLike(text) ||
            GoldTaskRequest.isAlertRequest(text))) {
      return null;
    }
    return r;
  }

  /// Returns null when [text] is not a reminder request at all. A reminder
  /// request that cannot be read returns a failed [ReminderRequest] whose
  /// error says so plainly.
  static ReminderRequest? parse(String text, DateTime now) {
    final lead = _lead.firstMatch(text);
    if (lead == null) return null;
    var rest = (lead.namedGroup('rest') ?? '').trim();
    if (rest.isEmpty) return ReminderRequest.fail(noTaskMessage);
    rest = rest.replaceFirst(
        RegExp(r'[\s,]+please$', caseSensitive: false), '');

    var dayWord = '';
    final dm = RegExp(r"\b(tomorrow|today)\b(?!')", caseSensitive: false)
        .firstMatch(rest);
    if (dm != null) {
      dayWord = dm.group(1)!.toLowerCase();
      rest = ('${rest.substring(0, dm.start)} ${rest.substring(dm.end)}')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    }

    RegExpMatch? m = _trailingAt.firstMatch(rest) ?? _leadingAt.firstMatch(rest);
    if (m != null) {
      final task = _cleanTask(m.namedGroup('task') ?? '');
      if (task.isEmpty) return ReminderRequest.fail(noTaskMessage);
      return _absolute(task, m.namedGroup('d')!, m.namedGroup('m'),
          m.namedGroup('ap'), dayWord, now);
    }
    m = _trailingIn.firstMatch(rest) ?? _leadingIn.firstMatch(rest);
    if (m != null) {
      final task = _cleanTask(m.namedGroup('task') ?? '');
      if (task.isEmpty) return ReminderRequest.fail(noTaskMessage);
      final token = m.namedGroup('n')!.toLowerCase();
      final unit = m.namedGroup('u')!.toLowerCase();
      final amount = RegExp(r'^\d+$').hasMatch(token)
          ? double.parse(token)
          : token.startsWith('half')
              ? 0.5
              : 1.0;
      final minutes = (amount * (unit.startsWith('h') ? 60 : 1)).round();
      if (minutes < 1) return ReminderRequest.fail(noTimeMessage);
      if (minutes > 7 * 24 * 60) return ReminderRequest.fail(tooFarMessage);
      return ReminderRequest.ok(
        task: task,
        when: now.add(Duration(minutes: minutes)),
        relative: true,
        afterMinutes: minutes,
      );
    }
    return ReminderRequest.fail(noTimeMessage);
  }

  static ReminderRequest _absolute(String task, String d, String? m,
      String? ap, String dayWord, DateTime now) {
    int hour;
    int minute;
    if (m != null) {
      if (d.length > 2) return ReminderRequest.fail(badTimeMessage);
      hour = int.parse(d);
      minute = int.parse(m);
    } else if (d.length >= 3) {
      hour = int.parse(d.substring(0, d.length - 2));
      minute = int.parse(d.substring(d.length - 2));
    } else {
      hour = int.parse(d);
      minute = 0;
    }
    if (minute > 59) return ReminderRequest.fail(badTimeMessage);
    final suffix = (ap ?? '').toLowerCase().replaceAll('.', '');
    final List<int> hours;
    if (suffix.isNotEmpty) {
      if (hour < 1 || hour > 12) return ReminderRequest.fail(badAmPmMessage);
      hours = [hour % 12 + (suffix == 'pm' ? 12 : 0)];
    } else {
      if (hour > 23) return ReminderRequest.fail(badTimeMessage);
      // "9:42" with no am or pm: take whichever of 9:42 am or 9:42 pm comes
      // next. The reply states the exact time so a wrong guess is visible.
      hours = (hour >= 1 && hour <= 12) ? [hour % 12, hour % 12 + 12] : [hour];
    }
    final offsets = dayWord == 'tomorrow'
        ? const [1]
        : dayWord == 'today'
            ? const [0]
            : const [0, 1];
    DateTime? best;
    for (final off in offsets) {
      for (final h in hours) {
        final c = DateTime(now.year, now.month, now.day + off, h, minute);
        if (c.isAfter(now) && (best == null || c.isBefore(best))) best = c;
      }
    }
    if (best == null) return ReminderRequest.fail(passedTodayMessage);
    final minutes =
        ((best.difference(now).inSeconds + 59) ~/ 60).clamp(1, 60 * 24 * 8);
    return ReminderRequest.ok(
      task: task,
      when: best,
      relative: false,
      afterMinutes: minutes,
    );
  }

  static String _cleanTask(String raw) {
    var t = raw.trim();
    t = t.replaceAll(
        RegExp(
            '^[\\s"\'\\u201C\\u201D\\u2018\\u2019`]+|[\\s"\'\\u201C\\u201D\\u2018\\u2019`,;:.]+\$'),
        '');
    t = t.replaceFirst(
        RegExp(r'^(?:to|that|about)\s+', caseSensitive: false), '');
    t = t.replaceFirst(
        RegExp(r'[\s,]+please$', caseSensitive: false), '');
    t = t.trim();
    if (t.length > 200) t = t.substring(0, 200).trim();
    return t;
  }
}
