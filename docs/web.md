# The browser build

An added target, not a port. The same code builds for iPad, for Android and
for a browser; what differs is behind conditional imports at the platform
boundary, and nothing about the tablet build changed to make the browser one
work.

Use it to let somebody try the app without an invitation, an Apple account or
a sideloaded APK. Do not use it as somebody's communication device — see
[What a browser cannot have](#what-a-browser-cannot-have).

## Build and serve

```sh
cd app
dart run build_runner build            # *.g.dart is generated, not committed
flutter build web --release
../tools/fetch_web_voice.sh            # 141 MB, once, into app/web/voice/
flutter build web --release            # again, so the voice lands in build/web
```

Then serve `app/build/web` as a static directory. Anything will do:

```sh
cd app/build/web && python3 -m http.server 8099
```

No headers are required. The WebAssembly build of the voice is
single-threaded, so there is no `SharedArrayBuffer` and no cross-origin
isolation to arrange — plain static hosting is enough. Serving `.wasm` as
`application/wasm` is still worth doing for CanvasKit.

Under a subdirectory, pass the path: `flutter build web --base-href /aac/`.

## What is in `web/`

| | |
|---|---|
| `sqlite3.wasm` | SQLite. Drift runs the board's database on it. |
| `drift_worker.js` | The worker drift puts the database behind, so a query does not block the board. |
| `kokoro_worker.js` | The neural voice's engine, in a thread of its own. |
| `voice/` | The model. Fetched by `tools/fetch_web_voice.sh`, never committed. |

The first two come from the [drift release][drift] matching the pinned
version. Bump them together with the package or the worker and the library
disagree about the protocol between them.

[drift]: https://github.com/simolus3/drift/releases

## The voice

`tools/fetch_web_voice.sh` downloads `kokoro-int8-en-v0_19` from the
`sherpa-onnx` release the tablet uses, unpacks it — nothing in a browser
decompresses bzip2, so it cannot be fetched at runtime the way the tablet
fetches it — trims espeak-ng's data to English, and writes a manifest the
worker reads.

**int8 rather than the tablet's fp32.** The fp32 weights are measurably
*faster* to run — wasm has no int8 dot product, so quantising costs more than
it saves — but they are 352 MB unpacked against 141 MB, and the first-run
download is what decides whether anybody sees the app at all. The eleven
voices are the same eleven.

`--full` keeps every language espeak ships, for anyone taking the files
somewhere else. The English trim saves 17 MB of dictionaries this board does
not speak.

A different location: `--dart-define=WORDBRIDGE_VOICE_URL=https://…/manifest.json`.

### Why the voice runs in a worker

Synthesis is a blocking call into WebAssembly and takes two to three seconds
for a word. A page has one thread. Run there it would stop the board drawing,
stop it taking taps, and — the part that decides the architecture — leave
nothing able to run the timer that gives up and falls back to the browser's
own voice. A board that will not answer and will not give up either is worse
than a slow one. This is the same reason the tablet pushes synthesis to an
isolate.

So `kokoro_worker.js` holds the module, the weights and the synthesis, and
only samples cross back.

### Hearing it

The voice is opt-in, the same as on a tablet, and the route to it is the same:

1. Press and hold the top-left corner of the sentence bar for two seconds.
2. Set a caregiver PIN — any four to six digits, first time only.
3. **Speech** → **Wordbridge voice** → **Download the voice**. 141 MB.
4. Back to the board.

**The first press of a word speaks in the browser's own voice.** That is the
ladder working, not failing: synthesis takes longer than the budget the press
is allowed to wait, so the word is said in whatever voice can say it
immediately — and the clip is filed as it lands. Press the same word again and
it is Kokoro. The sentence bar behaves the same way.

To have every word ready in advance, **Words made in advance** → **Start** on
the same screen. It is minutes of work and it is not started on its own: a
pack that dies with the page is not worth filling without being asked.

## What a browser cannot have

Stated on the caregiver screen too, under **This copy**, because a person
deciding needs to read it there rather than here.

- **No backups.** The board is in the browser's own storage. Clearing site
  data removes it and nothing can copy it somewhere safe first.
- **No import or export.** A board set cannot be written to a file or read
  from one.
- **No reports.** Faults are not recorded and nothing is sent.
- **Only the pictures that come with the app.** The sets that fetch a picture
  when a word needs one file it afterwards, and photographs are filed the same
  way.
- **The browser's own voices** are what the device voice falls back to, and
  they are frequently network-backed — which is the thing the tablet build
  deliberately excludes. Defensible in a demo, nowhere else.

Everything else is the shipped app: the vocabulary, the locations, the
editor, the grammar, prediction, breadcrumbs, profiles, the caregiver PIN.

## What holds here exactly as it does on a tablet

- **Fixed motor planning.** Cells are pre-materialised rows and positions never
  move. `app/test/motor_plan_invariant_test.dart` governs this build too.
- **The board keeps its shape.** A tablet is locked to the orientation the
  grid was derived for; a window is not, so the grid is drawn into a box of
  its own aspect and centred. Dragging a corner letterboxes it rather than
  squashing every cell — which would break the motor plan in the only units a
  hand knows, by the one route the invariant test cannot see.
- **Speech never waits on the database or the logger.**
- **ARASAAC and Sclera are not bundled.** `tools/check_symbol_boundary.sh`
  passes for this target as for any other.

## The seams

Each is a `foo.dart` that conditionally exports `foo_native.dart` or
`foo_web.dart`. Features call the seam and never ask what platform they are
on; a host that grows a capability changes one file rather than every branch
that mentioned it.

| seam | native | web |
|---|---|---|
| `platform/host.dart` | keeps files, backs up off device | neither, and says so |
| `db/sqlite_file.dart` | `VACUUM INTO`, `quick_check` over a file | refuses; backup is not offered |
| `features/speech/audio_output.dart` | the iOS audio session, the plugin's rate scale | nothing to route, and Web Speech's own scale |
| `features/speech/neural/kokoro.dart` | sherpa over FFI, in an isolate | the same engine in a worker |
| `features/speech/neural/clip_player.dart` | a platform channel | Web Audio |
| `features/speech/neural/clip_store.dart` | one file per voice per speed | this session, in memory |
| `features/speech/neural/voice_model.dart` | an archive, verified and unpacked | files, in the browser's cache |
| `features/grid/board_aspect.dart` | the OS holds the aspect | the app does |
| `features/grid/symbol_file.dart` | draws a file | there is no file |

The database needs no seam: `drift_flutter` takes web options and ignores them
everywhere else.
