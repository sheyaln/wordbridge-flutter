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

class UsageQueries {
  UsageQueries(this._db);

  final WordbridgeDatabase _db;

  static int _cutoff(Duration window) => nowMs() - window.inMilliseconds;

  /// The ways of choosing a word that mean the user went to the location.
  ///
  /// An allowlist rather than a list of exclusions, so a source added later
  /// has to be considered before it can count towards a motor plan. Partner
  /// modelling is not here — a partner demonstrating a word teaches the user,
  /// but it is not the user's own practice — and neither is a word taken from
  /// the prediction strip, which was never reached for at all.
  static const practisedSources = [UsageSource.touch, UsageSource.switchAccess];

  /// Selections recorded at a location, counting only the user's own reaches.
  ///
  /// This is what makes a remap warning honest rather than alarmist: the
  /// question is not "has this word been used" but "has this *position* been
  /// practised", which is what a motor plan actually is.
  Future<CellHistory> historyForCell(
    String cellId, {
    Duration window = const Duration(days: 90),
  }) async {
    final since = _cutoff(window);

    final rows =
        await (_db.select(_db.usageEvents)..where(
              (e) =>
                  e.cellId.equals(cellId) &
                  e.occurredAt.isBiggerOrEqualValue(since) &
                  e.source.isInValues(practisedSources),
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

  Future<List<WordCount>> mostUsedWords(
    String profileId, {
    Duration window = const Duration(days: 7),
    int limit = 50,
  }) async {
    final count = _db.usageEvents.id.count();
    final query = _db.selectOnly(_db.usageEvents)
      ..addColumns([_db.usageEvents.labelSnapshot, count])
      ..where(
        _db.usageEvents.profileId.equals(profileId) &
            _db.usageEvents.occurredAt.isBiggerOrEqualValue(_cutoff(window)) &
            _db.usageEvents.action.equalsValue(ButtonAction.speak) &
            _db.usageEvents.source.equalsValue(UsageSource.touch),
      )
      ..groupBy([_db.usageEvents.labelSnapshot])
      ..orderBy([OrderingTerm.desc(count)])
      ..limit(limit);

    return (await query.get())
        .map(
          (r) => (
            label: r.read(_db.usageEvents.labelSnapshot)!,
            count: r.read(count)!,
          ),
        )
        .toList();
  }

  /// Distinct words used — the metric SLPs track for vocabulary growth, and
  /// the one that goes into funding paperwork.
  Future<int> numberOfDifferentWords(
    String profileId, {
    Duration window = const Duration(days: 7),
  }) async {
    final distinct = _db.usageEvents.labelSnapshot.count(distinct: true);
    final query = _db.selectOnly(_db.usageEvents)
      ..addColumns([distinct])
      ..where(
        _db.usageEvents.profileId.equals(profileId) &
            _db.usageEvents.occurredAt.isBiggerOrEqualValue(_cutoff(window)) &
            _db.usageEvents.action.equalsValue(ButtonAction.speak) &
            _db.usageEvents.source.equalsValue(UsageSource.touch),
      );

    return (await query.getSingle()).read(distinct) ?? 0;
  }

  Future<List<DayCount>> activityByDay(String profileId, {int days = 7}) async {
    final rows =
        await (_db.select(_db.usageEvents)..where(
              (e) =>
                  e.profileId.equals(profileId) &
                  e.occurredAt.isBiggerOrEqualValue(
                    _cutoff(Duration(days: days)),
                  ) &
                  e.source.equalsValue(UsageSource.touch),
            ))
            .get();

    final buckets = <DateTime, int>{};
    for (final r in rows) {
      final d = DateTime.fromMillisecondsSinceEpoch(r.occurredAt);
      final key = DateTime(d.year, d.month, d.day);
      buckets[key] = (buckets[key] ?? 0) + 1;
    }

    final today = DateTime.now();
    return List.generate(days, (i) {
      final day = DateTime(
        today.year,
        today.month,
        today.day,
      ).subtract(Duration(days: days - 1 - i));
      return (day: day, count: buckets[day] ?? 0);
    });
  }

  /// Sentences the user actually built, most recent first.
  ///
  /// Usually the most meaningful thing a parent sees — a list of what their
  /// child said, rather than a statistic about it.
  Future<List<Utterance>> recentUtterances(
    String profileId, {
    int limit = 25,
  }) async {
    final rows =
        await (_db.select(_db.usageEvents)
              ..where(
                (e) =>
                    e.profileId.equals(profileId) &
                    e.utteranceId.isNotNull() &
                    e.action.equalsValue(ButtonAction.speak) &
                    e.source.equalsValue(UsageSource.touch),
              )
              ..orderBy([(e) => OrderingTerm.desc(e.occurredAt)])
              ..limit(limit * 12))
            .get();

    final grouped = <String, List<UsageEvent>>{};
    for (final r in rows) {
      grouped.putIfAbsent(r.utteranceId!, () => []).add(r);
    }

    final utterances = grouped.values.map((events) {
      events.sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
      return (
        text: events.map((e) => e.labelSnapshot).join(' '),
        at: DateTime.fromMillisecondsSinceEpoch(events.last.occurredAt),
      );
    }).toList()..sort((a, b) => b.at.compareTo(a.at));

    return utterances.take(limit).toList();
  }

  Future<int> totalTaps(
    String profileId, {
    Duration window = const Duration(days: 7),
  }) async {
    final count = _db.usageEvents.id.count();
    final query = _db.selectOnly(_db.usageEvents)
      ..addColumns([count])
      ..where(
        _db.usageEvents.profileId.equals(profileId) &
            _db.usageEvents.occurredAt.isBiggerOrEqualValue(_cutoff(window)) &
            _db.usageEvents.source.equalsValue(UsageSource.touch),
      );

    return (await query.getSingle()).read(count) ?? 0;
  }

  /// Deletes everything older than the retention window.
  Future<int> pruneOlderThan(Duration retention) {
    return (_db.delete(
      _db.usageEvents,
    )..where((e) => e.occurredAt.isSmallerThanValue(_cutoff(retention)))).go();
  }

  Future<int> deleteAllFor(String profileId) {
    return (_db.delete(
      _db.usageEvents,
    )..where((e) => e.profileId.equals(profileId))).go();
  }
}
