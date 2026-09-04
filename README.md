# wordbridge

A free, open source AAC app. Runs on a tablet, shows a grid of words and
pictures, speaks whatever is pressed.

This app was developed with the assistance of generative AI. It is said here,
on the About screen inside the app, and in the footer of the website, because
anyone deciding what this is allowed to do is entitled to know that before they
decide.

## Fixed motor planning

Every word has a permanent place on the grid. Adding vocabulary never moves
what is already there; new words go into cells left empty for them.

A grid location is a database row that exists whether or not a word sits on it.
Every cell is created with its board, empty, and its identity never changes.
Content attaches to a location, and every location is deliberate rather than
computed.

Despite evidence for consistent placement being thin (Thistle et al., 2018),
this was built because the mechanism is plausible, and muscle memory supports
the goal of making an AAC app that is intuitive.

## Editing

The editor is open to whoever knows the board, the user included, and holds one
rule:

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

Everything needed to speak is on the device, so nothing waits on a network.

What leaves it, and what does not:

- Usage tracking is on by default and asked about at setup. It records the
  location, never the word, and it never comes to us. It leaves the device by
  one route only, if somebody asked for it: inside a backup, into their own
  account.
- Crash reports are on by default and asked about at setup. They go out on the
  next launch, never during the crash, carrying a stack trace with quoted text
  and file paths removed.
- Voice measurements are off until somebody turns them on.
- A bug report or an idea is shown whole before it is sent, and somebody
  presses send.
- Backups are on the device, and a copy can also go to the family's own iCloud
  or Google account. Asked at setup, per device, and never switched on by an
  update. It goes to their account and never to us: there is no server of ours
  involved and no credential of ours in the app.

## Build

Flutter stable, currently 3.47 with Dart 3.13.

```sh
cd app
flutter pub get
dart run build_runner build   # generates the database code
flutter run
flutter test
```

Render tests carry the `golden` tag and are checked locally; a Linux runner
rasterizes text differently, so CI runs `flutter test --concurrency=1
--exclude-tags golden`.

Deploying: [Deploying to an iPad](docs/deploy-ipad.md).

## License

Code is MIT, see [LICENSE](LICENSE).

Symbol sets carry their own terms. Bundled sets permit commercial use with
attribution. Optional downloadable sets are available for noncommercial use.
