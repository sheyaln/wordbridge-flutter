# wordbridge

A free, open source communication app for people who do not speak. It runs on a
tablet, shows a grid of words and pictures, and says out loud whatever is
pressed.

**Status: early access.** It runs on one iPad and is not in any app store yet.
Do not put it on a device somebody depends on.

## Fixed motor planning

Every word has a permanent place on the grid, and adding vocabulary never moves
what is already there.

If `eat` is on the second row, fourth column today, it is on the second row,
fourth column in two years, after the vocabulary has tripled. New words go into
cells that were left empty for them. Nothing shifts to make room.

That permanence is what makes fluent speech possible. Someone who has to look
for a word is searching a picture grid, and searching costs seconds per word in
a conversation that will not wait. Someone whose finger already knows where the
word is has a remembered movement instead, the way a touch typist has a
movement for `k` rather than a search for it. The movement costs almost
nothing, and it is available under stress, in the dark, and while looking at
the person being spoken to.

**How the code guarantees it.** A grid location is a permanent database row
that exists whether or not a word sits on it. Every cell of a board is created
when the board is created, empty, and its identity never changes. Content
attaches to a location. A location is never computed from a list of words,
because computed layouts are how grid apps reshuffle in silence: delete the
twelfth button and everything after it slides up one cell, and no line of code
ever said "move eat".

`app/test/motor_plan_invariant_test.dart` records the route to every word,
simulates the vocabulary growing to full size, and fails the build if any
existing route changes by one byte. It blocks CI.

**What the evidence supports.** The direct experimental support for consistent
symbol placement is thin. It is essentially one study (Thistle et al., 2018) of
24 typically developing children aged four, in which the group with consistent
symbol placement roughly halved its selection time over five sessions while the
group with variable placement did not improve at all. That is a striking result
and it is one study, on children without disabilities, measuring response time.
wordbridge is built as though consistent placement matters, because the
mechanism is plausible and the cost of being wrong is low. It does not claim
more than that.

## The layout belongs to whoever knows the user

A word a person needs and cannot reach is not vocabulary. A sibling's name, a
food from their culture, a special interest, a second language: these arrive
from the family and the classroom, not from a shipped word list, and the person
who knows to add them is a parent, a teaching assistant, or a therapist rather
than a programmer.

That matters more than it sounds. Johnson et al. (2006), a survey of 275 AAC
specialists, found the driver of AAC abandonment ranked first was failure to
maintain and adjust the system. Yau et al. (2024) found 73 to 100% of
stakeholders reporting poor customization, with parents specifically struggling
to adjust vocabulary. A device that cannot be adjusted gets put in a drawer.

So the editor is open to the people around the user, and it protects the motor
plan while they work:

> **Additive changes are safe. Displacing changes are not.**

A change is *displacing* if a word the user has already learned moves,
disappears, or acquires a different route. Everything else is additive: filling
an empty cell, revealing a hidden one, editing a label or a picture or the
spoken text, adding a word, changing the voice. Additive edits are ordinary and
unceremonious.

| The editor's rule | What it buys |
|---|---|
| Hiding a word never frees its cell | Vocabulary can start small and grow without anything relocating. Unhide a word after six months and it is exactly where it always was. |
| Deleting is deliberate, and separate from hiding | The one action that permanently reclaims a location is never the quick one. |
| Moving a word tells you first how often that location was reached for | Usage is recorded against the location, not the word, so the count survives the edit and means what it says. |

A displacing edit is still possible, because sometimes it is genuinely the
right call. It arrives with its cost measured in the user's own history:

> Moving **eat** will change its motor pattern. Maya has tapped this location
> 341 times in the last 90 days. If she has learned this position, moving it
> may take weeks to relearn. Move anyway?

That dialog is the whole design in one screen. The software holds the
invariant; the person who knows the user makes the call.

## Speech never waits

Speech happens before anything else. Logging comes after, and the logger cannot
throw, so a database problem can never cost somebody a word.

Everything the app needs is on the device. No network for any core function, no
account, no sync, no phoning home on its own for a crash report or a metric or
on a timer. Bytes leave a device only because a person read what was in a
report and pressed send.

Usage tracking is off until somebody turns it on, because an AAC log is a
transcript of a disabled person's private speech.

## What it does today

| | |
|---|---|
| Fixed grid, positions stored rather than computed | done |
| Starter vocabulary: Universal Core 36 plus roughly 330 fringe words | done |
| Grid size chosen at setup from orientation and icon size, at any size | done |
| Automatic paging when a board needs a second page | done |
| Pinned question column and system row on every board | done |
| Bundled pictures across four symbol sets, plus your own photos | done |
| A picture is found automatically when a word is added, or left blank | done |
| Word endings (`+s`, `+ed`, `+ing`, `+'s`) with irregular verbs | done |
| Subject agreeing copula (`am`, `is`, `are`, `was`, `were`) and articles | done |
| Word prediction in its own strip, which never rearranges the grid | done |
| Breadcrumb trail showing the route taken to a word | done |
| On device speech, offline, with voice, tone, speed, pitch and volume | done |
| Profiles, each with its own board, settings and history | done |
| Caregiver mode behind a two corner hold and a PIN, with PIN recovery | done |
| Board editor: add, move, hide, delete, move between boards | done |
| Usage tracking, off by default, with a caregiver summary | done |
| Open Board Format import and export | done |
| Backups, versioned and restorable, visible in Files | done |

Not yet: cloud sync, eye gaze and head tracking, visual scene displays, message
banking. Scanning and switch access are parked until somebody who uses them can
be consulted, rather than guessed at.

## The boards are yours

Boards import and export as Open Board Format (`.obf` and `.obz`), which other
software reads. A vocabulary built here can be opened elsewhere, and one built
elsewhere can be brought in. Backups live in Files, so a caregiver can copy one
to iCloud Drive or Google Drive; the copy off the tablet is the one that
survives the tablet.

## Build and run

Flutter stable, currently 3.47 with Dart 3.13. The app is in `app/`.

```sh
cd app
flutter pub get
dart run build_runner build   # generates the database code
flutter run
```

Tests:

```sh
cd app
flutter test
```

The suite lives in `app/test/`, and `motor_plan_invariant_test.dart` is the one
that blocks merges. Golden tests carry the `golden` tag and are read locally:
they are rendered on macOS and a Linux runner rasterizes text differently, so
CI runs `flutter test --concurrency=1 --exclude-tags golden`.

Deploying to a device: [Deploying to an iPad](docs/deploy-ipad.md).

## License

Code is MIT. See [LICENSE](LICENSE).

Symbol sets are not covered by that and carry their own terms. The sets bundled
with the app permit commercial use with attribution, which is why the app has a
credits screen and this repository has a [NOTICE.md](NOTICE.md). Two further
sets are restricted to noncommercial use and are therefore never bundled: they
are optional downloads, so the restriction attaches to a user's choice rather
than to what this project ships. A CI check enforces that boundary. See
[Symbol packs](docs/symbol-packs.md).

## Read further

| | |
|---|---|
| [Architecture decisions](docs/adr/) | Start with [ADR 0001](docs/adr/0001-project-thesis.md) |
| [Starter vocabulary](docs/starter-vocabulary.md) | Where every shipped word came from |
| [Symbol packs](docs/symbol-packs.md) | The symbol sets and their licenses |
| [Reporting](docs/reporting.md) | How a crash or an idea reaches us, and what travels with it |
