import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../../db/database.dart';
import '../../db/ids.dart';
import '../../db/tables.dart';

/// Records what was selected, batched off the critical path.
///
/// Two hard rules, both about the same thing: nothing here may ever stand
/// between a user and their voice.
///
///  1. [log] returns immediately. It does not await, and it does not throw.
///  2. Every failure is swallowed and counted. A full disk or a locked
///     database costs the caregiver some statistics; it must never cost the
///     user a word.
///
/// Logging is also **off by default**. A complete transcript of a disabled
/// person's speech is not something to collect because it happens to be easy.
class UsageLogger {
  UsageLogger(this._db, {required this.deviceId});

  final WordbridgeDatabase _db;
  final String deviceId;

  final ValueNotifier<bool> _enabled = ValueNotifier(false);

  /// Opt-in, per the AAC user or whoever speaks for them.
  bool get enabled => _enabled.value;
  set enabled(bool value) => _enabled.value = value;

  /// Fires when [enabled] is switched, and only then.
  ///
  /// A screen reporting on the log has no other way to know it has stopped
  /// being written to, and waiting for whatever else happens to rebuild it
  /// means showing figures for a switch that has already been flipped. Nothing
  /// on the write path touches this: [log] reads the value and never notifies,
  /// so a listener costs a selection nothing.
  ValueListenable<bool> get enabledChanges => _enabled;

  final _pending = <UsageEventsCompanion>[];
  Timer? _flushTimer;

  /// Non-fatal write failures, surfaced in caregiver settings rather than
  /// thrown at the user.
  int droppedEvents = 0;

  static const _flushInterval = Duration(seconds: 2);
  static const _flushThreshold = 25;

  void log({
    required String profileId,
    required String vocabularyId,
    required String boardId,
    required String cellId,
    String? buttonId,
    required String label,
    required ButtonAction action,
    required UsageSource source,
  }) {
    if (!enabled) return;

    try {
      final now = nowMs();
      // No label, no utterance, no session (§4.71). Those three are what turn
      // a list of taps back into the sentences somebody said, and this table
      // exists to answer one question — how often this word has been reached
      // for where it currently sits — which needs none of them.
      _pending.add(
        UsageEventsCompanion.insert(
          deviceId: deviceId,
          profileId: profileId,
          vocabularyId: vocabularyId,
          boardId: boardId,
          cellId: cellId,
          buttonId: Value(buttonId),
          action: action,
          source: source,
          occurredAt: now,
        ),
      );

      if (_pending.length >= _flushThreshold) {
        unawaited(flush());
      } else {
        _flushTimer ??= Timer(_flushInterval, () => unawaited(flush()));
      }
    } catch (_) {
      droppedEvents++;
    }
  }

  Future<void> flush() async {
    _flushTimer?.cancel();
    _flushTimer = null;

    if (_pending.isEmpty) return;

    final batch = List<UsageEventsCompanion>.from(_pending);
    _pending.clear();

    try {
      await _db.batch((b) => b.insertAll(_db.usageEvents, batch));
    } catch (_) {
      droppedEvents += batch.length;
    }
  }

  Future<void> dispose() async {
    await flush();
    _flushTimer?.cancel();
    _enabled.dispose();
  }
}
