import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../../db/database.dart';
import '../../db/ids.dart';
import '../speech/neural/neural_voice.dart';
import '../speech/neural/synthesis_budget.dart';
import '../speech/tone.dart';
import '../talk/route_walk.dart';
import '../utterance/morphology.dart';
import 'grid_choice.dart';

/// Per-user preferences, held in the profile row.
///
/// Kept as JSON rather than columns because these are settings, not data: they
/// accumulate, they are read together, and adding one should not be a schema
/// migration on a device someone depends on.
class ProfileSettings extends ChangeNotifier {
  ProfileSettings(this._db, this.profileId);

  final WordbridgeDatabase _db;
  final String profileId;

  Map<String, dynamic> _values = {};
  bool _loaded = false;

  bool get isLoaded => _loaded;

  /// Show word endings only where they can actually be used.
  ///
  /// On by default. A key that does nothing when pressed is one a user learns
  /// to distrust, and there is no way for them to know why it failed. Some
  /// teams prefer every key visible at all times so the board never changes
  /// shape, which is why this is a setting and not a rule.
  bool get contextualGrammar => _values['contextualGrammar'] as bool? ?? true;

  /// Hide other verbs once a verb has been chosen, until something licenses
  /// another one.
  ///
  /// Off by default. It removes clutter mid-sentence at the cost of a board
  /// that changes shape while you use it.
  bool get filterVerbs => _values['filterVerbs'] as bool? ?? false;

  /// Return to the root board after speaking, so every word costs the same
  /// number of movements every time.
  ///
  /// On by default, because it is what makes a word's motor path fixed rather
  /// than dependent on where the user happened to be. Off suits someone
  /// building longer utterances out of one category, who would otherwise pay
  /// the navigation cost again for every word.
  bool get autoReturn => _values['autoReturn'] as bool? ?? true;

  /// How long the board ignores taps after it changes.
  ///
  /// A user moving at speed through a learned sequence has their finger coming
  /// down before the new board has finished arriving, and lands on whatever
  /// now occupies that location — a word they did not mean, in a sentence they
  /// cannot easily repair.
  ///
  /// This is the one place something deliberately stands between a user and
  /// speech, so it is short, adjustable, and can be switched off entirely by
  /// setting it to zero.
  /// A quarter of a second, down from half. Long enough to swallow the tap
  /// that was aimed at the board that just left, short enough that it does
  /// not read as the device thinking.
  ///
  /// Named because four places need this number and a build with no settings
  /// object still has to pause for the same length as one that has them.
  /// Written out four times it drifted the moment one of them was changed.
  static const defaultSettleDelay = Duration(milliseconds: 250);

  Duration get settleDelay {
    final ms = _values['settleDelayMs'] as int?;
    return ms == null ? defaultSettleDelay : Duration(milliseconds: ms);
  }

  /// How long the board rests on each key while it walks a route to a word
  /// found in Find a word.
  ///
  /// A second was a number somebody typed, and it is too fast for the thing it
  /// is for: the point of the walk is that a person watches where the keys are
  /// so their hand can go there next time, and a beat that outruns the eye
  /// teaches the route to nobody. Two seconds is the default, and it is
  /// adjustable because how long that takes is a fact about a person rather
  /// than about the board.
  Duration get walkBeat =>
      Duration(milliseconds: _values['walkBeatMs'] as int? ?? 2000);

  /// The two answers the grid was derived from.
  ///
  /// Stored so the settings screen can show what was chosen rather than only
  /// its consequence, and so changing one can be recognized as the deliberate,
  /// expensive act it is. Nothing reads these to lay a board out — the board
  /// was laid out once, when the profile was made.
  BoardOrientation get orientation =>
      _enum('orientation', BoardOrientation.values, BoardOrientation.landscape);

  IconSize get iconSize => _enum('iconSize', IconSize.values, IconSize.medium);

  /// The chosen voice, as the platform names it.
  ///
  /// Null means whatever the device defaults to. Stored as a name and locale
  /// pair rather than an index, because the list of installed voices changes
  /// when the OS updates and an index would quietly become a different voice.
  String? get voiceName => _values['voiceName'] as String?;

  String? get voiceLocale => _values['voiceLocale'] as String?;

  /// The platform's own handle for the voice, where it gives one. Two voices
  /// can share a name at different qualities, and only this tells them apart.
  String? get voiceIdentifier => _values['voiceIdentifier'] as String?;

  /// Offer the platform's joke voices — robots, singing, cartoon characters.
  ///
  /// Off by default. They crowd out the speaking voices on a screen where
  /// somebody is choosing how another person will sound, and the platform
  /// lists a lot of them.
  bool get noveltyVoices => _values['noveltyVoices'] as bool? ?? false;

  /// How fast, high and loud this profile's voice is, before tone.
  ///
  /// One is the engine's own default for each. Volume is a fraction of what
  /// the device is set to and cannot exceed it — see [Tone] for what platform
  /// speech can and cannot be made to do.
  double get speechRate => _double('speechRate', 1.0);

  double get speechPitch => _double('speechPitch', 1.0);

  double get speechVolume => _double('speechVolume', 1.0);

  Tone get tone => Tone.byName(_values['tone'] as String?);

  /// Speak with the downloaded neural voice rather than the platform's.
  ///
  /// Off by default and off for every profile that predates it, because it is
  /// an opt-in that costs 360 MB and half an hour before it sounds like
  /// anything. Switching it off restores §4.4 exactly: the platform voice, the
  /// same dials, the same four tones.
  bool get neuralVoice => _values['neuralVoice'] as bool? ?? false;

  /// Which of the model's voices, by the model's own name for it.
  ///
  /// A name rather than an index, for the reason [voiceName] is: a model
  /// update that reorders the table would otherwise leave a person speaking as
  /// somebody else without a thing having changed on screen.
  String get neuralVoiceId =>
      _values['neuralVoiceId'] as String? ?? defaultNeuralVoiceId;

  /// How long the bar's speak key may wait before the platform voice takes
  /// over, as `base + perWord × words`.
  ///
  /// Stored per profile because it is measured on the device this profile is
  /// used on. The shipped default is the floor device's number doubled, and
  /// every supported tablet is faster than the floor device — see
  /// [SynthesisBudget].
  SynthesisBudget get synthesisBudget {
    final base = _values['synthesisBudgetBaseMs'];
    final perWord = _values['synthesisBudgetPerWordMs'];
    if (base is! num || perWord is! num) return SynthesisBudget.shipped;
    return SynthesisBudget(
      base: Duration(milliseconds: base.toInt()),
      perWord: Duration(milliseconds: perWord.toInt()),
    ).sane;
  }

  /// Whether the budget above was measured here or is still the default.
  ///
  /// The screen says which, because "about two seconds" is a claim about a
  /// particular tablet and a fifteen-word sentence on the floor device is
  /// nearer six.
  bool get synthesisBudgetMeasured =>
      _values['synthesisBudgetBaseMs'] is num &&
      _values['synthesisBudgetPerWordMs'] is num;

  /// Records a budget measured on this device.
  Future<void> setSynthesisBudget(SynthesisBudget budget) async {
    await set('synthesisBudgetBaseMs', budget.base.inMilliseconds);
    await set('synthesisBudgetPerWordMs', budget.perWord.inMilliseconds);
  }

  double _double(String key, double fallback) {
    final stored = _values[key];
    return stored is num ? stored.toDouble() : fallback;
  }

  /// Offer likely next words in a strip above the grid.
  ///
  /// On for profiles created from here, and not free: the strip takes its
  /// height from the grid, so every button is a little shorter. Profiles that
  /// predate it were written down as not having it, so the fallback here is
  /// only ever reached by a profile made after it existed. Switching it off
  /// restores the previous layout exactly — nothing is rebuilt and no cell
  /// moves, so this is the one layout change that costs nothing to undo.
  bool get prediction =>
      _values['prediction'] as bool? ?? predictionForNewProfiles;

  /// What a profile created from here is given for [prediction].
  static const predictionForNewProfiles = true;

  /// Show the route to the word just spoken along the bottom of the screen.
  ///
  /// On for profiles created from here. The strip takes its height from the
  /// grid, so profiles that predate it were written down as not having it and
  /// this fallback is only ever reached by a profile made after it existed.
  /// Switching it off restores the previous layout exactly — nothing is
  /// rebuilt and no cell moves.
  bool get breadcrumbs =>
      _values['breadcrumbs'] as bool? ?? breadcrumbsForNewProfiles;

  /// What a profile created from here is given for [breadcrumbs].
  ///
  /// A default has to be written at creation rather than fall out of the
  /// getter, so that it reaches new profiles without reaching boards that were
  /// laid out before it existed.
  static const breadcrumbsForNewProfiles = true;

  /// How the copula keys choose between the forms of "to be".
  ///
  /// Cycling by default, because it never says a word it then has to take
  /// back. Unlike the two strips, this default may live in the getter and
  /// reach profiles that predate it: no cell moves, no button changes size,
  /// and the first press produces the same word under either answer. The two
  /// differ only from the second press onwards, which under the other answer
  /// did nothing a person would want.
  CopulaMode get copulaMode =>
      _enum('copulaMode', CopulaMode.values, CopulaMode.toggle);

  /// Whether "can" followed by "not" is spoken as "can't" (§4.42).
  ///
  /// On, because "can not" is not a sentence anybody says out loud and the
  /// board is somebody's speech rather than a transcript of their keystrokes.
  /// Off is offered because it is a house style rather than a correctness fix:
  /// a team teaching the two words separately wants to hear the two words.
  ///
  /// Safe as a getter default, and safe to reach a board built before it
  /// existed, because it changes what is spoken and never where anything is.
  bool get contractions => _values['contractions'] as bool? ?? true;

  /// Whether two numerals in a row are one number (§4.74).
  ///
  /// Off by default, which is today's behavior: somebody counting two things
  /// presses `1` then `2` and means *one two*. Joining is the choice, made by
  /// a caregiver who knows which the person at the tablet is doing.
  bool get joinNumbers => _values['joinNumbers'] as bool? ?? false;

  /// Who presses the keys on the way to a word the finder found (§4.47).
  ///
  /// The key waits, by default. The board pressing the keys itself shows
  /// somebody the route; the key waiting makes them walk it, and walking it is
  /// what lays down the motor plan this whole app is built to protect. A
  /// found word that the board fetches teaches the person nothing about where
  /// it lives.
  ///
  /// This was `presses` for as long as it was the only mode. Changing it is
  /// safe here and would not be later: no profile has learned the old one, and
  /// a default moved under somebody who had is the displacement this app
  /// exists to refuse.
  WalkMode get walkMode => _enum('walkMode', WalkMode.values, WalkMode.waits);

  /// Whether each key speaks as it is pressed (§4.48).
  ///
  /// On by default, which is what shipped. Off leaves the board silent until
  /// the sentence is sent — a choice between hearing each key and hearing the
  /// finished sentence, not a mute: the sentence key is untouched either way.
  bool get speakEachWord => _values['speakEachWord'] as bool? ?? true;

  /// Name each run of locations by what it is for.
  ///
  /// Off by default. It is scaffolding for the people teaching a board rather
  /// than for the person speaking on it, and the strip takes its space from
  /// the grid, so every button is a little shorter while it is on. Turning it
  /// off puts them back exactly as they were: nothing is rebuilt and no cell
  /// moves.
  bool get regionLabels => _values['regionLabels'] as bool? ?? false;

  /// Whether strong language is revealed on the boards that carry it.
  ///
  /// The words are already placed either way; this only draws them. Turning it
  /// off hides them in place, so turning it back on puts them exactly where
  /// they were.
  bool get profanity => _values['profanity'] as bool? ?? false;

  /// Whether this person's selections are recorded.
  ///
  /// Per profile rather than per device, because what it records is one
  /// person's speech and consent to that is theirs. Switching profile switches
  /// this with it.
  ///
  /// **On, and asked about at setup** (§7). A usage log is a complete
  /// transcript of a disabled person's private conversation, so the question
  /// is put plainly on the setup screen with both answers spelled out rather
  /// than buried in a settings list nobody opens.
  ///
  /// It is on by default because the editor's one real safeguard reads from
  /// it: without a log, "moving this word will cost 341 taps of practice" has
  /// no number in it, and the warning that makes a displacing edit visible
  /// degrades to a shrug. A profile that predates the question keeps its
  /// stored answer either way.
  ///
  /// The recording never comes to us. What is defaulted on is keeping a local
  /// record, not sending one anywhere.
  ///
  /// It can leave the tablet by exactly one route, and only where somebody
  /// asked for it: a backup is the whole database, so a copy kept in the
  /// family's own iCloud or Google account carries the log with it. See
  /// `features/backup/cloud_backup.dart`, which is why that question is a
  /// device-level one put at setup rather than a default.
  bool get usageTracking => _values['usageTracking'] as bool? ?? true;

  /// What a profile created without an answer is given.
  ///
  /// Named so that setup and this getter cannot drift into disagreeing about
  /// what "not asked" means.
  static const usageTrackingForNewProfiles = true;

  /// Whether a report may carry how the neural voice is performing (§4.52).
  ///
  /// Its own answer, and deliberately not [usageTracking]'s. One is "record
  /// which locations are selected, on this tablet, for the editor to read".
  /// The other is "measurements about the voice may leave with a report I
  /// send". They are different questions and one answer must not stand for the
  /// other.
  ///
  /// Off unless somebody said yes, on the same principle.
  bool get voiceMeasurements => _values['voiceMeasurements'] as bool? ?? false;

  /// What a profile created without an answer is given. Named for the same
  /// reason as the others: setup and this getter must not drift into
  /// disagreeing about what "not asked" means.
  static const voiceMeasurementsForNewProfiles = false;

  /// Whether a fault this tablet caught is sent without being asked (§4.59).
  ///
  /// **Sent on the next launch, never during the crash.** The handler that
  /// records a fault installs before the app does: it has no database and no
  /// profile, and the fault it is holding may be the database. A network call
  /// from inside an error handler on a device that has just failed is how one
  /// fault becomes two. So the record is written when it happens and the
  /// waiting ones go out later, when the app is working and nobody is mid
  /// sentence.
  ///
  /// On by default, and asked at setup. What it sends is a stack trace with
  /// quoted text and file paths taken out, plus the version, the hardware and
  /// the grid — no board words and no names.
  bool get crashReports => _values['crashReports'] as bool? ?? true;

  /// What a profile created without an answer is given.
  static const crashReportsForNewProfiles = true;

  T _enum<T extends Enum>(String key, List<T> values, T fallback) {
    final stored = _values[key];
    for (final value in values) {
      if (value.name == stored) return value;
    }
    return fallback;
  }

  Future<void> load() async {
    final row = await (_db.select(
      _db.profiles,
    )..where((p) => p.id.equals(profileId))).getSingleOrNull();

    if (row != null) {
      try {
        _values = Map<String, dynamic>.from(
          jsonDecode(row.settingsJson) as Map,
        );
      } catch (_) {
        _values = {};
      }
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> set(String key, Object? value) async {
    _values = {..._values, key: value};
    notifyListeners();

    // An update, never an upsert. Writing a setting must not be able to
    // overwrite a profile's name or unpick which vocabulary it points at.
    final written =
        await (_db.update(
          _db.profiles,
        )..where((p) => p.id.equals(profileId))).write(
          ProfilesCompanion(
            settingsJson: Value(jsonEncode(_values)),
            updatedAt: Value(nowMs()),
          ),
        );

    // An update against a profile that is not there writes nothing and reports
    // success. Silently losing a caregiver's setting is the single most
    // reported failure of the app this one exists to replace, so it fails
    // loudly rather than pretending to have saved.
    if (written == 0) {
      throw StateError(
        'No profile "$profileId" to save settings to. "$key" was not stored.',
      );
    }
  }
}
