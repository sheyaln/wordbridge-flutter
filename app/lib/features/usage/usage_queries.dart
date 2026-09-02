import 'package:drift/drift.dart';

import '../../db/database.dart';
import '../../db/ids.dart';
import '../../db/tables.dart';

typedef WordCount = ({String label, int count});
typedef DayCount = ({DateTime day, int count});
typedef Utterance = ({String text, DateTime at});

/// How much a location has been used, and therefore how much a user may have
/// learned about where it is.
typedef CellHistory = ({int taps, int days, DateTime? firstUsed});

/// The [days] calendar days ending on [today], oldest first, each at local
/// midnight.
///
/// Stepped by date rather than by a twenty-four hour duration, because a local
/// day is 23 or 25 hours long across a daylight-saving change and an axis built
/// from durations stops landing on the midnights that day buckets are keyed by.
/// Out-of-range day numbers normalize, so month and year ends need no case of
/// their own.
List<DateTime> calendarDaysEnding(DateTime today, int days) => [
  for (var i = days - 1; i >= 0; i--)
    DateTime(today.year, today.month, today.day - i),
];

/// Whole calendar days from [from] to [to], counting date changes rather than
/// elapsed time.
///
/// Rounded through hours because the 23- and 25-hour days either side of a
/// daylight-saving change would otherwise gain or lose one.
int calendarDaysBetween(DateTime from, DateTime to) {
  final start = DateTime(from.year, from.month, from.day);
  final end = DateTime(to.year, to.month, to.day);
  return (end.difference(start).inHours / 24).round();
}

/// How far back a figure looks, resolved to an epoch cutoff when the query runs.
///
/// The two kinds answer different questions and a figure has to carry the one
/// it was labeled with. "Today" ends at the last local midnight whatever the
/// hour, so a number shown under that word never quietly includes yesterday
/// evening — these numbers reach funding letters.
class UsageWindow {
  const UsageWindow.rollingDays(this.days) : _calendar = false;
  const UsageWindow.calendarDays(this.days) : _calendar = true;

  final int days;
  final bool _calendar;

  int cutoffMs() => _calendar
      ? calendarDaysEnding(DateTime.now(), days).first.millisecondsSinceEpoch
      : nowMs() - Duration(days: days).inMilliseconds;
}

class UsageQueries {
  UsageQueries(this._db);

  final WordbridgeDatabase _db;

  /// Answers "did the user go to this location" — the motor-plan question.
  ///
  /// An allowlist rather than a list of exclusions, so a source added later
  /// has to be considered before it can count toward a motor plan. A word
  /// taken from the prediction strip is not here: it was never reached for,
  /// and counting it would inflate the tap count a caregiver is shown before
  /// moving a button. Neither is partner modeling — a partner demonstrating
  /// a word teaches the user, but it is not the user's own practice.
  static const practicedSources = [UsageSource.touch, UsageSource.switchAccess];

  /// Answers "what language did the user produce" — every figure and every
  /// sentence on a report.
  ///
  /// The prediction strip counts here and not in [practicedSources] because
  /// those are two questions, not two wordings of one. A strip word was never
  /// reached for, so it is no evidence about a location; the user still chose
  /// it and the device said it out loud, so it is language they produced.
  /// These figures reach funders as evidence of how much a person says, and
  /// leaving the strip out understates that. Partner modeling is outside both
  /// — that is another person talking on the user's device.
  static const spokenSources = [
    UsageSource.touch,
    UsageSource.switchAccess,
    UsageSource.prediction,
  ];

  /// Selections recorded at a location, counting only the user's own reaches.
  ///
  /// This is what makes a remap warning honest rather than alarmist: the
  /// question is not "has this word been used" but "has this *position* been
  /// practiced", which is what a motor plan actually is.
  /// [occupantId] scopes the count to the word that is in the cell now (§4.71).
  ///
  /// The sentence this number ends up in is *this word has been reached for
  /// here this often*, and a count carried over from whatever used to sit in
  /// the location makes that sentence false. A location does not accumulate a
  /// lifetime of taps across every word that has ever held it.
  ///
  /// Null counts everything in the cell, which is only what a caller with no
  /// occupant to name can mean.
  /// Forgets a location's counts, because the word in it changed (§4.71).
  ///
  /// Filtering by occupant alone would leave the old counts on disk answering
  /// a question nobody may ask again, which is the same mistake as keeping the
  /// transcript. A count that has stopped being true is deleted.
  Future<int> forgetCell(String cellId) =>
      (_db.delete(_db.usageEvents)..where((e) => e.cellId.equals(cellId))).go();

  Future<CellHistory> historyForCell(
    String cellId, {
    String? occupantId,
    UsageWindow window = const UsageWindow.rollingDays(90),
  }) async {
    final since = window.cutoffMs();

    final rows =
        await (_db.select(_db.usageEvents)..where(
              (e) =>
                  e.cellId.equals(cellId) &
                  e.occurredAt.isBiggerOrEqualValue(since) &
                  e.source.isInValues(practicedSources) &
                  (occupantId == null
                      ? const Constant(true)
                      : e.buttonId.equals(occupantId)),
            ))
            .get();

    if (rows.isEmpty) {
      return (taps: 0, days: 0, firstUsed: null);
    }

    final days = rows
        .map((r) {
          final d = DateTime.fromMillisecondsSinceEpoch(r.occurredAt);
          return DateTime(d.year, d.month, d.day);
        })
        .toSet()
        .length;

    final first = rows.map((r) => r.occurredAt).reduce((a, b) => a < b ? a : b);

    return (
      taps: rows.length,
      days: days,
      firstUsed: DateTime.fromMillisecondsSinceEpoch(first),
    );
  }

  Future<int> totalTaps(
    String profileId, {
    UsageWindow window = const UsageWindow.rollingDays(7),
  }) async {
    final count = _db.usageEvents.id.count();
    final query = _db.selectOnly(_db.usageEvents)
      ..addColumns([count])
      ..where(
        _db.usageEvents.profileId.equals(profileId) &
            _db.usageEvents.occurredAt.isBiggerOrEqualValue(window.cutoffMs()) &
            _db.usageEvents.source.isInValues(spokenSources),
      );

    return (await query.getSingle()).read(count) ?? 0;
  }

  /// Deletes everything older than the retention window.
  Future<int> pruneOlderThan(Duration retention) {
    final cutoff = nowMs() - retention.inMilliseconds;
    return (_db.delete(
      _db.usageEvents,
    )..where((e) => e.occurredAt.isSmallerThanValue(cutoff))).go();
  }

  Future<int> deleteAllFor(String profileId) {
    return (_db.delete(
      _db.usageEvents,
    )..where((e) => e.profileId.equals(profileId))).go();
  }
}
