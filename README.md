# wordbridge

A free, open source communication app for people who do not speak. Runs on a
tablet, shows a grid of words and pictures, speaks whatever is pressed.

**Early access.** Runs on one iPad, not in any app store. Do not put it on a
device somebody depends on.

## Fixed motor planning

Every word has a permanent place on the grid. Adding vocabulary never moves
what is already there; new words go into cells left empty for them.

A grid location is a database row that exists whether or not a word sits on it.
Every cell is created with its board, empty, and its identity never changes.
Content attaches to a location. Locations are never computed from a list of
words, because computed layouts are how grid apps reshuffle in silence.

`app/test/motor_plan_invariant_test.dart` records the route to every word,
grows the vocabulary to full size, and fails if any existing route changes. It
blocks CI.

Evidence for consistent placement is thin: one study (Thistle et al., 2018),
24 typically developing four year olds. Built as though it matters because the
mechanism is plausible and the cost of being wrong is low. No more than that.

## Editing

The editor is open to parents, aides and therapists, and holds one rule:

> Additive changes are safe. Displacing changes are not.

Displacing means a word already learned moves, disappears, or gets a different
route. Everything else is additive and unceremonious.

- Hiding a word never frees its cell.
- Deleting is deliberate, and separate from hiding.
- Moving a word first reports how often that location was reached for. Usage is
  recorded against the location, not the word, so the count survives the edit.

Displacing edits are still possible, with the cost shown first.

## Speech

Speech happens before anything else. Logging comes after and cannot throw, so a
database problem never costs somebody a word.

Everything needed is on the device. Bytes leave because a person read a report
and pressed send. Usage tracking is off until somebody turns it on.

## Shipped

Fixed grid with stored positions · Universal Core 36 plus ~330 fringe words ·
grid size chosen at setup · automatic paging · pinned question column and system
row · four bundled symbol sets plus your own photos · automatic picture lookup ·
word endings and irregular verbs · subject agreeing copula and articles · word
prediction in its own strip · breadcrumb trail · offline on device speech with
voice, tone, speed, pitch, volume · profiles · caregiver mode behind a two
corner hold and PIN · board editor · usage tracking with caregiver summary ·
Open Board Format import and export · versioned backups in Files.

Not yet: cloud sync, eye gaze, head tracking, visual scene displays, message
banking. Scanning and switch access are parked until somebody who uses them can
be consulted.

## Build

Flutter stable, currently 3.47 with Dart 3.13.

```sh
cd app
flutter pub get
dart run build_runner build   # generates the database code
flutter run
flutter test
```

Goldens carry the `golden` tag and are read locally; a Linux runner rasterizes
text differently, so CI runs `flutter test --concurrency=1 --exclude-tags
golden`.

Deploying: [Deploying to an iPad](docs/deploy-ipad.md).

## License

Code is MIT, see [LICENSE](LICENSE).

Symbol sets carry their own terms. Bundled sets permit commercial use with
attribution, hence the credits screen and [NOTICE.md](NOTICE.md). Two further
sets are noncommercial and are never bundled: they are optional downloads, so
the restriction attaches to a user's choice rather than to what ships here. A CI
check enforces the boundary. See [Symbol packs](docs/symbol-packs.md).

## Docs

| | |
|---|---|
| [Architecture decisions](docs/adr/) | Start at [ADR 0001](docs/adr/0001-project-thesis.md) |
| [Starter vocabulary](docs/starter-vocabulary.md) | Where every shipped word came from |
| [Symbol packs](docs/symbol-packs.md) | The sets and their licenses |
| [Reporting](docs/reporting.md) | How a crash or an idea reaches us |
