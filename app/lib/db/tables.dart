import 'package:drift/drift.dart';

/// Whether a grid location currently holds a word.
///
/// A reserved cell is not an absence — it is a location deliberately held
/// open so vocabulary can grow into it later without displacing anything.
enum CellState { emptyReserved, occupied }

enum ButtonAction {
  speak,
  navigate,
  back,
  home,
  clear,
  backspace,
  speakBar,
  morpheme,

  /// Ends the sentence with a mark that carries tone.
  ///
  /// Platform speech engines read sentence-final punctuation for prosody, so a
  /// question mark buys a genuine rising intonation rather than an imitation
  /// of one. It is the only tone control available without a bundled neural
  /// voice, and it costs one location.
  punctuate,

  /// Turns the window of category keys along the system row.
  ///
  /// The keys stay where they are; what each one opens changes. A board of
  /// categories would put every one of them two movements away instead of one.
  cycleCategories,

  none,
}

enum MorphemeKind {
  pluralS,
  pastEd,
  ing,
  comparativeEr,
  superlativeEst,
  possessive,
}

/// Forms of "to be", which agree with the subject rather than transforming
/// the previous word, so they append instead of rewriting.
enum CopulaKind { present, past }

enum SymbolSource { bundled, downloaded, custom }

/// Distinguishes the AAC user's own selections from a partner modeling on
/// their device. Conflating them makes every progress report wrong.
///
/// [prediction] is separate from [touch] for a second reason: the remap
/// warning counts how often a *location* was reached for, and a word taken
/// from the prediction strip was not reached for at all. Counting it would
/// inflate the number a caregiver is shown before they move something.
enum UsageSource { touch, switchAccess, partnerModel, prediction }

enum EditKind {
  remap,
  create,
  hide,
  unhide,
  relabel,
  resymbol,
  delete,
  gridResize,
}

enum PartOfSpeech {
  pronoun,
  verb,
  adjective,
  noun,
  preposition,
  question,
  adverb,
  conjunction,
  negation,
  determiner,
  social,
  other,
}

/// Which part of speech to color convention a vocabulary uses. Clinicians are
/// split between these and the literature is consistent that internal
/// consistency matters far more than which scheme is chosen.
enum ColorConvention { modifiedFitzgerald, goossens, custom }

enum BoardKind { root, category, system }

mixin _Timestamps on Table {
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  /// Soft delete. Hard deletes are unmergeable if sync is ever added, and
  /// destroy the ability to resolve historical usage rows.
  IntColumn get deletedAt => integer().nullable()();
}

class Profiles extends Table with _Timestamps {
  TextColumn get id => text()();
  TextColumn get displayName => text().withLength(min: 1, max: 100)();
  TextColumn get avatarUri => text().nullable()();
  TextColumn get activeVocabularyId => text().nullable()();

  /// Sets the starting vocabulary, and nothing else.
  ///
  /// Stored rather than the age it implies, so a profile does not silently
  /// keep a four-year-old's word list once its owner is nine. Nullable: a
  /// caregiver who would rather not record a birthday gets the middle preset
  /// and full control, not an interrogation.
  IntColumn get birthDate => integer().nullable()();

  /// Render filter: buttons at or below this level are visible. Raising it is
  /// how vocabulary grows, and it never moves anything already placed.
  IntColumn get vocabLevel => integer().withDefault(const Constant(1))();

  /// Voice, rate, pitch, gain, activation mode, dwell/debounce ms,
  /// auto-return, speak-on-tap vs speak-on-send.
  TextColumn get settingsJson => text().withDefault(const Constant('{}'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// A board set. Grid geometry lives here rather than on [Boards] because motor
/// planning depends on absolute finger position: if two boards in one
/// vocabulary had different dimensions, the same slot would land under a
/// different finger and the plan would be destroyed.
class Vocabularies extends Table with _Timestamps {
  TextColumn get id => text()();

  /// Null marks a shipped template rather than a user's working copy.
  TextColumn get profileId => text().nullable().references(Profiles, #id)();

  TextColumn get name => text()();
  TextColumn get locale => text().withDefault(const Constant('en-US'))();

  IntColumn get gridRows => integer()();
  IntColumn get gridCols => integer()();

  TextColumn get rootBoardId => text().nullable()();

  /// Positions of home/back/clear/backspace, identical on every board.
  /// JSON: {"home": [6, 0], "back": [6, 1], ...}
  TextColumn get systemCellMap => text().withDefault(const Constant('{}'))();

  /// Renamed from `color_scheme` at schema 8. The values are the enum's own
  /// names and none of them changed, so the migration is the column and
  /// nothing else.
  TextColumn get colorConvention => textEnum<ColorConvention>().withDefault(
    const Constant('modifiedFitzgerald'),
  )();

  BoolColumn get isTemplate => boolean().withDefault(const Constant(false))();

  /// Attribution for imported or derived board sets.
  TextColumn get sourceLicense => text().nullable()();

  BoolColumn get motorPlanLocked =>
      boolean().withDefault(const Constant(true))();
  IntColumn get schemaVersion => integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {id};
}

class Boards extends Table with _Timestamps {
  TextColumn get id => text()();
  TextColumn get vocabularyId => text().references(Vocabularies, #id)();
  TextColumn get name => text()();
  TextColumn get kind => textEnum<BoardKind>()();

  /// Which lines each band of this board occupies, as JSON.
  ///
  /// The layout engine works this out once and nothing recomputes it, so it is
  /// stored for the same reason coordinates are: a board is what the database
  /// says it is, not what a function would say if asked again. It is what lets
  /// the grid name a region — the rightmost column as questions, a run of
  /// columns as verbs — without inferring the grouping from the words that
  /// happen to be in it.
  ///
  /// Null on a board built before it was recorded, and on one a caregiver made
  /// by hand, which has no bands.
  TextColumn get bandMap => text().nullable()();

  /// Names a caregiver chose for lines of this board, as JSON (§4.26).
  ///
  /// Kept separate from [bandMap] so that what the layout decided and what a
  /// person chose can never be confused for one another, and keyed by **line
  /// index** rather than by band: a board a caregiver made by hand has no
  /// bands at all, and naming a row is exactly what it needs.
  ///
  /// A rebuild (§4.20) or a grid change re-lays the board, so line 3 afterwards
  /// is not the line 3 that was named. Both discard these rather than carry a
  /// name onto a different row, and both say so.
  TextColumn get lineNames => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// The motor-plan anchor, and the reason this schema exists.
///
/// Every location on every board is materialized at board creation and its id
/// is permanent — never reused, never deleted. Positions are therefore stored
/// rather than derived from an ordered list of buttons; a derived layout
/// silently relocates every subsequent word whenever one is inserted or
/// removed, which is the exact failure this project exists to prevent.
///
/// Usage is recorded against cells rather than words so tap history survives
/// content changes, which is what makes the remap impact warning possible.
class Cells extends Table {
  TextColumn get id => text()();
  TextColumn get boardId => text().references(Boards, #id)();

  IntColumn get row => integer()();
  IntColumn get col => integer()();

  IntColumn get spanRows => integer().withDefault(const Constant(1))();
  IntColumn get spanCols => integer().withDefault(const Constant(1))();

  TextColumn get state =>
      textEnum<CellState>().withDefault(const Constant('emptyReserved'))();

  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {boardId, row, col},
  ];
}

/// Content attached to a location.
///
/// [cellId] is nullable so a remap can be performed as an atomic three-step
/// swap under the partial unique index, and so the editor can hold words that
/// have no home yet in an unplaced tray.
class Buttons extends Table with _Timestamps {
  TextColumn get id => text()();
  TextColumn get cellId => text().nullable().references(Cells, #id)();
  TextColumn get vocabularyId => text().references(Vocabularies, #id)();

  TextColumn get label => text()();

  /// Appended to the utterance bar.
  TextColumn get message => text()();

  /// Spoken instead of [message] when they should differ. Maps to Open Board
  /// Format's `vocalization`.
  TextColumn get speakText => text().nullable()();

  TextColumn get action => textEnum<ButtonAction>()();
  TextColumn get targetBoardId => text().nullable().references(Boards, #id)();
  TextColumn get morphemeKind => textEnum<MorphemeKind>().nullable()();

  TextColumn get symbolId => text().nullable().references(Symbols, #id)();
  TextColumn get partOfSpeech => textEnum<PartOfSpeech>().nullable()();

  TextColumn get backgroundColor => text().nullable()();
  TextColumn get borderColor => text().nullable()();
  TextColumn get textColor => text().nullable()();

  /// Masked, but the cell stays occupied. Hiding must never free a location,
  /// or the next word added would take it and the motor plan would break.
  BoolColumn get hidden => boolean().withDefault(const Constant(false))();

  IntColumn get vocabLevel => integer().withDefault(const Constant(1))();

  /// home/back/clear/backspace — edit-locked behind an advanced toggle.
  BoolColumn get isSystem => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class Symbols extends Table {
  TextColumn get id => text()();

  /// Which pack this came from, so a pack can be swapped or removed wholesale.
  TextColumn get packId => text().nullable()();

  TextColumn get source => textEnum<SymbolSource>()();

  /// Upstream identifier within the pack, for re-resolution after a cache wipe.
  TextColumn get externalId => text().nullable()();

  TextColumn get localUri => text().nullable()();
  TextColumn get label => text()();

  TextColumn get license => text()();
  TextColumn get attribution => text()();

  /// Deduplicates repeated custom uploads of the same photo.
  TextColumn get contentHash => text().nullable()();

  IntColumn get width => integer().nullable()();
  IntColumn get height => integer().nullable()();

  IntColumn get lastUsedAt => integer().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Append-only. Integer key rather than UUID because merging two logs is
/// concatenation, not reconciliation.
/// How often a location was selected, and nothing else (§4.71).
///
/// **Deliberately not a transcript.** This carried the word each tap said, the
/// utterance it belonged to and the sitting it happened in — enough to
/// reconstruct somebody's conversations, sitting in a file on a device other
/// people pick up, about a person who may not be able to object.
///
/// What it is for is one sentence in the editor: *this location has 341 taps
/// in the last 90 days, moving it will cost that*. A count against a cell
/// answers that. The word does not, the order does not, and the grouping into
/// sentences never did.
class UsageEvents extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get deviceId => text()();
  TextColumn get profileId => text()();
  TextColumn get vocabularyId => text()();
  TextColumn get boardId => text()();

  /// The location. Survives the word being relabeled or moved away.
  TextColumn get cellId => text()();

  TextColumn get buttonId => text().nullable()();

  TextColumn get action => textEnum<ButtonAction>()();

  /// Whose selection it was. Kept because a word taken from the prediction
  /// strip was never reached for, and counting it would inflate the one number
  /// this table exists to report.
  TextColumn get source => textEnum<UsageSource>()();

  IntColumn get occurredAt => integer()();
}

/// Audit trail for anything that touches the motor plan. Cheap to write, and
/// it buys single-tap undo, an answer to "what did the school SLP change on
/// Tuesday", and the tap counts shown in the remap warning.
class EditEvents extends Table {
  TextColumn get id => text()();
  TextColumn get profileId => text().nullable()();
  TextColumn get vocabularyId => text()();
  TextColumn get cellId => text().nullable()();
  TextColumn get buttonId => text().nullable()();

  TextColumn get kind => textEnum<EditKind>()();
  TextColumn get beforeJson => text().nullable()();
  TextColumn get afterJson => text().nullable()();

  /// Selections recorded at the affected location before the edit, so the
  /// cost of a displacing change is stated in the user's own history.
  IntColumn get motorImpactTaps => integer().nullable()();

  IntColumn get changedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Single row. The salt lives in the platform keystore, never here, so a
/// database dump alone does not yield the PIN.
class CaregiverAuth extends Table {
  TextColumn get id => text()();
  TextColumn get pinHash => text()();
  TextColumn get pinAlgo =>
      text().withDefault(const Constant('sha256-salted'))();
  IntColumn get failedAttempts => integer().withDefault(const Constant(0))();
  IntColumn get lockedUntil => integer().nullable()();
  BoolColumn get biometricEnabled =>
      boolean().withDefault(const Constant(false))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Device-wide state that belongs to no particular profile.
///
/// Currently just which profile was last in use, so launching resumes it
/// rather than showing a chooser. A chooser in the user's path is a screen
/// they cannot read, in front of the only way they have to speak.
class AppState extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// How often one word followed another in this profile's own sentences.
///
/// Counts, not a transcript. There is no timestamp and no ordering beyond the
/// pair, so this can rank what comes next without being able to reconstruct
/// anything that was said — which matters, because the alternative is keeping
/// a record of a disabled person's private speech in order to autocomplete it.
///
/// Separate from [UsageEvents] on purpose. That log is consent-gated, exports,
/// and is off by default; this one exists only while prediction is switched on
/// and is emptied when it is switched off.
class PredictionPairs extends Table {
  TextColumn get profileId => text()();

  /// Empty for the start of a sentence, so the first word can be predicted
  /// from nothing but how often the user opens with it.
  TextColumn get previous => text()();

  TextColumn get word => text()();

  IntColumn get count => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {profileId, previous, word};
}

/// Unused in v1. Present so that adding sync later is not a migration of every
/// table in the schema.
class SyncMeta extends Table {
  TextColumn get entity => text()();
  TextColumn get entityId => text()();
  IntColumn get localRev => integer().withDefault(const Constant(0))();
  IntColumn get serverRev => integer().nullable()();
  BoolColumn get dirty => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {entity, entityId};
}
