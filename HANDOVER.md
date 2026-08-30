# Neural voice — handover

Everything below was measured on **Haley's iPad mini 5 (A12, 3 GB, iOS 18.7.8)**
unless it says otherwise. That device is the floor, not the target, and every
published number for this model comes from something faster.

## What to merge

Two branches. They are independent and neither touches app code.

| Branch | Contents | Merge |
|---|---|---|
| `neural-voice` | One commit, `REQUIREMENTS.md` §4.5 only | Straight into `master`. No code, no conflicts unless someone else edited §4.5. |
| `voicebench` | The dev app in `voicebench/`, plus `run-bench.sh` and `set-team.sh` | Straight into `master`. New directory, nothing shared with `app/`. |

**`app/` is deliberately unchanged on both.** `sherpa_onnx` was added to
`app/pubspec.yaml` during the spike and then removed — do not merge a branch
that reintroduces it until the engine is actually being built, because an
unused native dependency costs binary size on a device that is short of space.

> ⚠️ While this work ran, another session had uncommitted changes to
> `app/lib/db/database.dart`, `main.dart`, `caregiver_home.dart`,
> `backup_service.dart` and new backup/pre-migration files in the same working
> tree. Nothing here touches those. If `app/pubspec.yaml` conflicts, the
> `sqlite3` move from dev-dependencies to dependencies is **theirs** and should
> be kept.

## The four gates, answered

### Gate 1 — the cache is cheap. Passes, not close.

The set to pre-synthesise is **1231 strings, not 377**: 444 bare words across
the three age presets, **782 inflected forms**, 5 copula forms. The endings are
the majority and are easy to forget — a morpheme key speaks the form it
produced (`wanted`, `eating`, `leg's`), so each is its own clip.

Measured by synthesising all of them and encoding as they would ship:

| | |
|---|---|
| Audio | 999 s over 1231 words |
| After trimming padding | 701 s |
| **AAC 24 kbps** | **7 MB per tone** |
| **AAC 48 kbps** | **9 MB per tone** |

Six tones ≈ 54 MB against a 92–326 MB model. **The cache is the small half.**

Two things only measuring found:

- **Kokoro pads; 30% of the bytes are silence.** `I` synthesises to 660 ms.
  Trim before storing — it is also the difference between a tap that speaks and
  a tap that pauses first.
- **Container overhead is ~2.5× the audio at this length.** 3.4 KB of AAC
  becomes an 8.2 KB `.m4a`. At half a second a clip the header *is* the file.
  Store packed, or as blobs in the database beside everything else. Do not
  write 1231 little files.

### Gate 2 — live synthesis is slow, and that decided the architecture

Release build, `sherpa_onnx`, Kokoro v0.19 fp32, 2 threads, after warm-up:

| | |
|---|---|
| One word | **1309 ms** mean (824–1780) |
| One sentence | **1670–2493 ms** |
| RTF | **1.95** |
| Baking all 1231 words | **27 min** per tone |

Fitted against utterance length: **1149 ms fixed + 197 ms/word** (±200 ms,
five points; `voicebench`'s Measure button gives eight).

The cost is dominated by **fixed per-call overhead**, not by length. That single
fact drives the timeout design below.

Reference points, so nobody quotes the wrong one: the same model reports RTF
0.62 on an A12X and 4–4.5× real time through the **Core ML** five-stage build
on an A17. `sherpa_onnx` is plain onnxruntime and gets none of that. Whether
Core ML closes the ~3× gap on an A12 is open and worth answering.

### Gate 3 — the mechanism is real; no tone is shippable

**Kokoro's 256-float style vector splits cleanly.** Dims `0:128` = timbre,
`128:256` = prosody. Transplanting the prosody half behaved identically on
three pairs — the output keeps the recipient's timbre and takes the donor's
pitch:

| donor prosody → recipient timbre | donor f0 | result f0 | MFCC dist donor / recipient |
|---|---|---|---|
| af_heart → am_michael | 217.1 | 216.6 | 45.6 / **7.1** |
| af_bella → am_fenrir | 208.4 | 202.5 | 108.2 / **12.1** |
| bf_emma → am_adam | 187.9 | 188.4 | 51.1 / **14.5** |

This is the shape a tone needs and it maps onto §4.4's existing rule: **the tone
supplies prosody, the profile's voice supplies timbre.** It is not symmetric —
the reverse direction produced a degenerate near-monotone once — so a tone must
be checked on each voice, not assumed.

**But the shipped voices do not span emotion.** PCA over all 54 voices' prosody
halves: first axis is 20.6% of variance and walking it moves *only* pitch
(f0 165.6 → 269.8, spread and duration unchanged). Axes 2–5 move nothing
measurable. Two steps out, synthesis collapses.

> **So the pitch dial already does what Kokoro's voices offer.** A neural voice
> does not earn its place by being neural. Do not ship emotion presets built on
> this — they would be the speed and pitch sliders wearing names they have not
> earned, which is exactly what ADR-0005 forbids.

What *is* beyond the dials sits in the **timbre** half: its third axis swings
spectral tilt 0.917 → 0.554. That is breathiness — the whisper §4.4 could not
build — and it is entangled with speaker identity, which is the wrong place.

**Kokoro ships no style encoder** (`decoder only: no diffusion, no encoder
release`), so reference audio cannot be turned into a style vector at all.

**StyleTTS 2 does ship the encoder**, so the same test ran there with emotional
reference clips. Result: **arousal transfers, valence does not.** Angry and
happy raise energy, tilt and pitch spread consistently across two speakers, and
calm lands nearest neutral. **`sad` came out higher-pitched than neutral in both
speakers** — the wrong direction. Two further defects: tempo does not transfer
at all (duration flat 1.77–2.10 s across every emotion), and speaker identity
leaks badly (MFCC drift to 149 — the tone changes *who you sound like*).

### Gate 4 — provenance, unresolved and it should gate shipping

Kokoro's weights are Apache-2.0. Its model card states the training data
includes *"synthetic audio generated by closed TTS models from large
providers"*. Those providers generally forbid training on their output. This
project enforces a symbol licence boundary in CI (`tools/check_symbol_boundary.sh`)
and publishes what it could not verify; a voice does not get a lower standard
than a picture. **NOTICE.md needs an answer, or a different model.**

StyleTTS 2 publishes LJSpeech and LibriTTS checkpoints — LibriTTS being
LibriVox public domain — which is the cleaner provenance *and* the model with
the encoder gate 3 needs. Gates 3 and 4 point the same way.

## What to implement, in order

1. **`SpeechEngine` gains a cached implementation.** Interface is already
   engine-agnostic; keep it that way. Lookup by (text, voice, tone) → audio
   blob. This is the whole tap path and it must never miss into a wait.
2. **The bake as a resumable background job**, not a modal progress bar. 27 min
   per tone. Bake the profile's default tone first so the board is usable long
   before the rest lands.
3. **The cache-miss ladder**: cached neural → live neural (bar press only,
   under timeout) → platform TTS. Rung 3 is a *different voice*, which is a
   real cost, not graceful degradation. It must be visible and it must never
   wait.
4. **The timeout**, `base + perWord × words`. See gotchas — it does not work
   without an isolate.
5. **Only then the bar's tone control.** §4.5 has the design; it is grounded in
   Pullin & Hennig (2015) and needs no new research.

Ship the **voice** before the **tones**. They are separable and the voice half
is good today.

## Gotchas, all of them paid for

- **`generate()` is a blocking FFI call.** On the main isolate it freezes the UI
  *and* leaves no thread able to notice a deadline, so the timeout cannot fire.
  `OfflineTts.fromPtr` is public: pass `tts.ptr.address` to `Isolate.run`, call
  `initBindings()` inside, rebuild with `Pointer.fromAddress`. Do **not** build
  a second engine in the isolate — a second 330 MB model does not fit beside the
  first on 3 GB. `voicebench/lib/main.dart` `_generateOffThread` is the pattern.
- **A late result must never speak.** If the fallback already spoke, drop the
  neural audio or the sentence is said twice, second time in a different voice.
  `FlutterTtsEngine.speak` already has the newest-wins pattern to copy.
- **`voices.bin` is validated against the model's own metadata**, not its file
  size. Kokoro v0.19 declares `n_speakers=11`; anything else fails with
  `Corrupted --kokoro-voices ... Expected #floats: 1438976`. You cannot widen
  the table. To use a custom style, rewrite the 11 existing slots and reload.
  Layout is `[speaker][511 tokens][256 floats]` float32.
- **Changing the voices file means reloading the model.** Budget for it, and
  time it on screen rather than guessing.
- **`devicectl device copy to --destination Documents/` copies a directory's
  *contents*, not the directory.** Also, copying a folder into a directory that
  already holds files **replaces** them — this silently wiped `model.onnx` and
  produced a "model missing" that looked exactly like a broken build. Copy the
  whole tree in one call, then verify by listing before launching.
- **The subcommand is `copy to` / `copy from`**, not `toDevice`/`fromDevice`.
- **Delete stale generated files on launch.** A bad `voices_*.bin` from an
  earlier build gets loaded in preference to being rebuilt, so the app keeps
  crashing after the bug is fixed.
- **A new bundle id needs an Apple ID in Xcode → Settings → Accounts.** A valid
  cert and an existing profile for a *different* id are not enough:
  `No Accounts: Add a new account in Accounts settings`.
- **Never install a spike over `org.wordbridge.wordbridge`.** Same bundle id
  replaces the app somebody speaks with. The data container survives, but the
  app does not.
- **int8 Kokoro is slower than fp32** in the published iOS benchmark. Do not
  quantise for speed without measuring.
- **`torch.load` needs `weights_only=False`** for StyleTTS 2 checkpoints under
  torch ≥ 2.6, and its phonemiser needs `nltk punkt_tab`.

## Open questions

- Does the **Core ML** five-stage build close the ~3× gap on an A12? It is the
  difference between a bar press that waits and one that does not.
- Can emotion be **disentangled from speaker identity** in StyleTTS 2 well
  enough that a tone does not change who the user sounds like?
- Where do tone vectors come from at ship time — a licensed corpus, or
  **caregiver-recorded reference clips**? The second sidesteps gate 4 entirely
  and is worth considering on its own merits.
- The **fitted timeout** should be measured per device at setup, not shipped as
  a constant. RTF 1.95 means a 15-word sentence is ~4 s, so no setting screen
  may say "about two seconds".
