# Continuation prompt — build the neural voice milestone

You are picking up wordbridge's optional local neural voice. The research is
done and measured; **this task is to build it**, not to re-derive it.

**Read `HANDOVER.md` on the `voicebench` branch first.** It has every number,
every gotcha, and why each decision was made. Do not re-litigate what is in it —
it was measured on the actual target device, not read about.

## The milestone

**Ship the voice. Do not ship tones.**

An opt-in, downloadable, strictly-local neural voice that replaces platform TTS
for a profile that switches it on, with pre-synthesised audio on the tap path
and live synthesis on the bar press.

Tones are explicitly **out of scope**. Gate 3 measured that Kokoro's prosody
space is one axis and that axis is pitch, so `sad`/`stern` presets would be the
speed and pitch sliders wearing names they have not earned — which ADR-0005
forbids. Voice and tone are separable and the voice half is good today.

## Ground rules that are not yours to change

- **Local only.** No network for synthesis, ever. The model download is the one
  network call and it is user-initiated.
- **§5 non-negotiable 1 stands by default.** A tap speaks instantly, from cache.
  The *only* sanctioned wait is the bar's speak key, only for a profile that
  opted in, only under the timeout below. This exception is recorded in §4.5;
  do not widen it.
- **§5 non-negotiable 9 applies to voices.** Never ship a control that does not
  do what its name says.
- **Never install a spike over `org.wordbridge.wordbridge`.** Same bundle id
  replaces the app somebody speaks with. Use `voicebench` for experiments.

## Build order — each step ships on its own

1. **`SpeechEngine` gains a neural implementation.** The interface in
   `app/lib/features/speech/speech_engine.dart` is already engine-agnostic and
   must stay that way — `FlutterTtsEngine` is not deleted, it becomes the
   fallback. Add `sherpa_onnx` to `app/pubspec.yaml` at this step and not
   before.
2. **Model store.** Download, verify, install to Documents (never the cache —
   OS eviction of a cache directory is a communication outage). ~360 MB. Show
   size before starting; resumable; deletable.
3. **The cache.** Lookup `(text, voice) -> audio blob`. Blobs in the database
   beside everything else, or one packed file — **not 1231 little files**, the
   container header is 2.5x the audio at half a second a clip. Trim leading and
   trailing silence: Kokoro pads, and it is 30% of the bytes.
4. **The bake, as a resumable background job.** 1231 strings, ~27 min. Not a
   modal progress bar. Survives being interrupted and resumed. Bake the
   profile's default voice first so the board is usable long before it finishes.
5. **The miss ladder**: cached neural -> live neural (bar press only, under
   timeout) -> platform TTS. Rung 3 is a *different voice*, which is a real
   cost, not graceful degradation: make it visible, and **never let it wait**.
6. **The timeout**, `base + perWord x words`. Fitted on the target device at
   **747 ms + 262 ms/word (R2 0.990)** — ship the default at roughly twice that
   and re-measure per device at setup. A timeout that fires in normal use is a
   random voice generator, not a safety net.
7. **Caregiver UI**: switch it on, download, bake progress, voice picker
   (previewed as a spoken sentence, like every other control in §4.4), how much
   of the vocabulary is baked, and how often the fallback fired.

## The gotchas that will cost you a day each

- **`generate()` is a blocking FFI call.** On the main isolate it freezes the UI
  *and* leaves no thread able to notice a deadline, so the timeout cannot fire
  at all. `OfflineTts.fromPtr` is public: pass `tts.ptr.address` into
  `Isolate.run`, call `initBindings()` inside, rebuild with
  `Pointer.fromAddress`. **Do not build a second engine in the isolate** — a
  second 330 MB model does not fit beside the first on 3 GB. Working pattern:
  `voicebench/lib/main.dart`, `_generateOffThread`.
- **A late result must never speak.** If the fallback already spoke, drop the
  neural audio or the sentence is said twice, the second time in a different
  voice. `FlutterTtsEngine.speak` already has the newest-wins pattern.
- **`voices.bin` is validated against the model's metadata, not its file size.**
  Kokoro v0.19 declares `n_speakers=11`; anything else fails with `Corrupted
  --kokoro-voices ... Expected #floats: 1438976`. Layout is
  `[speaker][511 tokens][256 floats]` float32.
- **The word list is 1231, not 377.** 444 bare words across the three age
  presets plus **782 inflected forms** plus 5 copulas — a morpheme key speaks
  the form it produced (`wanted`, `eating`, `leg's`), so each needs its own
  clip. Walk the seed the way `vocab_level_calibration_test` does.
- **int8 Kokoro is slower than fp32** in the published iOS benchmark. Do not
  quantise for speed without measuring.

## Your device

**Haley's iPad mini 5 — A12, 3 GB, `17098DA6-61DE-5465-9EA0-34CE0782F3C9`.**
Deploy with `tools/deploy-ipad.sh`. This is the floor, not the target: the same
model reports RTF 0.62 on an A12X and 4-4.5x real time through Core ML on an
A17, so anything that feels acceptable here is comfortable everywhere else.

**The simulator is not yours** — another agent is using it, and it runs on the
Mac's CPU anyway, so it cannot tell you anything about latency. Every timing
claim must come from the iPad.

## Done means

- A profile with the neural voice on speaks every board word instantly, from
  cache, in the chosen voice.
- The bar press speaks the sentence in that voice, or falls back to the platform
  voice inside the budget — never later, never twice.
- Turning it off restores today's behaviour exactly, and deleting the model
  reclaims the disk.
- The tap path is not measurably slower than it is today. Measure it; do not
  assume it.
- `flutter test` passes, `motor_plan_invariant_test` included. Nothing here
  touches a cell, and if it does, that is the bug.

## Do not

- Ship an emotion preset of any kind.
- Put live synthesis on the tap path.
- Add `sherpa_onnx` to `app/pubspec.yaml` before step 1.
- Reintroduce the `sqlite3` dev-dependency move in `app/pubspec.yaml` — that
  belongs to another session's backup work and should be left as it is.
