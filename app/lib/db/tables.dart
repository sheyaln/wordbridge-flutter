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
  none,
}

enum MorphemeKind { pluralS, pastEd, ing, comparativeEr, superlativeEst, possessive }

enum SymbolSource { bundled, downloaded, custom }

/// Distinguishes the AAC user's own selections from a partner modelling on
/// their device. Conflating them makes every progress report wrong.
enum UsageSource { touch, switchAccess, partnerModel }

enum EditKind { remap, create, hide, unhide, relabel, resymbol, delete, gridResize }

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

/// Which part-of-speech-to-colour convention a vocabulary uses. Clinicians are
/// split between these and the literature is consistent that internal
/// consistency matters far more than which scheme is chosen.
enum ColourScheme { modifiedFitzgerald, goossens, custom }

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

  TextColumn get colourScheme =>
      textEnum<ColourScheme>().withDefault(const Constant('modifiedFitzgerald'))();

  BoolColumn get isTemplate => boolean().withDefault(const Constant(false))();

  /// Attribution for imported or derived board sets.
  TextColumn get sourceLicense => text().nullable()();

  BoolColumn get motorPlanLocked => boolean().withDefault(const Constant(true))();
  IntColumn get schemaVersion => integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {id};
}

class Boards extends Table with _Timestamps {
  TextColumn get id => text()();
  TextColumn get vocabularyId => text().references(Vocabularies, #id)();
  TextColumn get name => text()();
  TextColumn get kind => textEnum<BoardKind>()();

  @override
  Set<Column> get primaryKey => {id};
}

/// The motor-plan anchor, and the reason this schema exists.
///
/// Every location on every board is materialised at board creation and its id
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
class UsageEvents extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get deviceId => text()();
  TextColumn get profileId => text()();
  TextColumn get vocabularyId => text()();
  TextColumn get boardId => text()();

  /// The location. Survives the word being relabelled or moved away.
  TextColumn get cellId => text()();

  TextColumn get buttonId => text().nullable()();

  /// What the button said at the time. Without this, editing a button would
  /// retroactively rewrite history and the caregiver's data would be a lie.
  TextColumn get labelSnapshot => text()();

  TextColumn get action => textEnum<ButtonAction>()();
  TextColumn get source => textEnum<UsageSource>()();

  TextColumn get sessionId => text()();
  TextColumn get utteranceId => text().nullable()();

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
  TextColumn get pinAlgo => text().withDefault(const Constant('sha256-salted'))();
  IntColumn get failedAttempts => integer().withDefault(const Constant(0))();
  IntColumn get lockedUntil => integer().nullable()();
  BoolColumn get biometricEnabled => boolean().withDefault(const Constant(false))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
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
