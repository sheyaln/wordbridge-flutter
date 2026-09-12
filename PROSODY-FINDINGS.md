# Prosody findings — punctuation, whisper, loudness

Measured against the shipped model, **Kokoro v0.19 int8** as it sits in
`wordbridge-web/app/web/voice/kokoro-int8-en-v0_19`, through `sherpa-onnx`
1.13.8 — the same engine `kokoro.dart` calls. Scripts in the session
scratchpad; every number below is reproducible from the model on disk.

This continues `TONE-RESEARCH.md`, which parked *emotional* tone (calm, stern,
sad) after the listening test. Nothing here revisits that. These are the three
questions it left untouched: sentence-final punctuation, whisper, and loudness.

## 1. Punctuation is plumbed correctly. The model ignores it.

The app's half is right, end to end, and worth stating so nobody re-does it:

- `Utterance.text` joins marks without a leading space — `you want that?`, not
  `you want that ?` — and the comment there already says why.
- `KokoroSynthesizer.textForModel` strips `,;:` but **preserves** a trailing
  `.!?…`, and appends `.` only when none is present.
- `?` `!` `.` are real entries in `tokens.txt` (ids 6, 5, 4). They reach the
  model as tokens, and the audio does change — a question and a statement are
  never byte-identical.

So the wiring is not the problem. **The model is.** Terminal f0 movement across
the final 300 ms of voiced speech, 12 sentences per voice, `?` against `.`:

| voice | sid | `.` | `?` | `!` | **? − .** | rose on |
|---|---|---|---|---|---|---|
| af | 0 | −2.44 st | −1.85 st | −2.17 st | **+0.58** (sd 2.90) | 4/12 |
| af_bella | 1 | −0.52 st | −0.68 st | −0.52 st | **−0.16** (sd 3.02) | 4/12 |
| am_adam | 5 | −0.77 st | +1.91 st | −0.50 st | **+2.68** (sd 2.70) | 7/12 |

An English yes/no question carries a terminal rise of roughly **+4 to +12
semitones**. Two of the three voices produce nothing distinguishable from
noise, and the third produces about half a rise on rather more than half of
its sentences. `!` is not distinct from `.` on any voice.

**There is no text-level lever either.** Capitals and repeated marks do
nothing measurable — same word, `af`, sid 0:

| text | dur | f0 | rms |
|---|---|---|---|
| `help.` | 0.48 | 239.2 | 0.0777 |
| `help!` | 0.46 | 238.3 | 0.0768 |
| `help!!!` | 0.47 | 238.4 | 0.0763 |
| `HELP!` | 0.46 | 239.6 | 0.0766 |
| `help?!` | 0.45 | 234.6 | 0.0769 |

Within measurement noise of each other on every axis. Kokoro's phonemizer
normalises the case away and the duration predictor does not count exclamation
marks. `length_scale` is not a lever either — it is exactly `1/speed`
(`length_scale` 0.8 and `speed` 1.25 both give 1.37 s), not an independent
prosody control.

### What would actually make a question sound like one

Post-process the contour. The cue is narrow, well understood and does not
require the model's cooperation: **raise f0 across the final voiced syllable by
4–8 semitones.** It is a pitch shift on the last ~250 ms of an existing buffer,
so it is deterministic, it runs on a cached clip, and it costs no synthesis.

It fits the architecture rather than fighting it. A sentence ending `?` is
already its own cache key — `you want that?` and `you want that.` are separate
entries — so the shifted clip is stored once and every later press is a cache
read. Nothing on the tap path changes.

The honest caveat, and it is the ADR-0005 argument again: a terminal rise
applied to a clip is a rise, not an interrogative prosody. It will read as a
question on short sentences that end on a stressed syllable and will read as
odd on sentences that do not. **It needs the same listening check the tones
failed**, on real sentences, before it is offered — and it is a far smaller
claim than the tones were, because a rise at the end is one cue rather than a
whole emotional register.

## 2. Whisper is reachable, and it is not the volume dial

ADR-0005 says a whisper is a different phonation rather than a quieter voice,
and declines to ship `Quiet` under a whisper's name. That is correct, and it is
now measured rather than asserted.

Whispering is voiced excitation replaced by noise with the formants left alone.
On a buffer that is STFT magnitude preserved, phase randomised per bin, plus a
gentle high shelf. Five sentences, `af`:

| variant | HNR | spectral centroid | rms |
|---|---|---|---|
| normal | **3.66 dB** | 3124 Hz | 0.0667 |
| `Quiet` (×0.25) | **3.66 dB** | 3124 Hz | 0.0167 |
| whisper (DSP) | **0.97 dB** | 4088 Hz | 0.0499 |

**`Quiet` has byte-identical harmonicity and spectral shape to normal.** It is
the same phonation at a lower level, exactly as the ADR says — the table is the
receipt. The DSP version drops harmonicity by 2.7 dB and moves the centroid up
by ~960 Hz, which is the direction real whispered speech moves.

Two things this does not settle. The absolute HNR figures are low because the
estimator is a normalised-autocorrelation proxy rather than a proper cepstral
HNR — read the *contrast*, not the levels. And phase randomisation smears
transients, so plosives soften; an LPC source-filter resynthesis with a noise
excitation would be cleaner and is the better implementation if this is
pursued. **Nobody has listened to it yet**, which given how `TONE-RESEARCH.md`
ended is the only gate that decides anything.

## 3. Loudness: the mechanism is built, unreachable, and has a dead line in it

This is the gap ADR-0005 names as "the most-wanted half" — the parent who
cannot hear their son from the back seat. The neural path is the one thing that
can close it, because the app owns the samples.

**`toPcm16` already takes a `gain`. Nothing ever passes one.** Every call site
— `KokoroSynthesizer.generate`'s own default, the bake, the live path — leaves
it at 1.0. The capability `audio_clip.dart` documents in its first paragraph
("made louder than the tablet's own maximum") is currently unreachable from the
app.

**And the soft clip is an identity function.** `audio_clip.dart:72`:

```dart
if (gain != 1.0) v = math.tan(math.atan(v));
```

`tan(atan(v)) == v` for all finite `v`. Verified:

| in | −3.0 | −1.7 | −0.5 | 0.5 | 1.7 | 3.0 |
|---|---|---|---|---|---|---|
| `tan(atan(in))` | −3.0 | −1.7 | −0.5 | 0.5 | 1.7 | 3.0 |
| `tanh(in)` | −0.995 | −0.935 | −0.462 | 0.462 | 0.935 | 0.995 |

The line does nothing and control falls through to the hard clamp two lines
below. The comment directly above it says the shaping is "`tanh`-like rather
than a hard clip" because "clipping a voice does not make it louder, it makes
it fuzzy" — and a hard clip is precisely what ships. `dart:math` has no `tanh`,
which is the likely origin. At gain ×6, **3.37% of samples hit the clamp**.

So the fix is two independent pieces, and the first is free:

**Headroom first, distortion never.** Measured source peak on a synthesised
sentence is **0.625** — about 4 dB of headroom the model leaves on the table on
every clip. Peak-normalising each clip as it is stored is a pure win: louder,
zero added distortion, no runtime cost, and it also evens out the clip-to-clip
level differences that make a composed phrase sound uneven. Do this before
reaching for gain at all.

**Then a real limiter for the rest.** Past normalisation, `tanh(v * gain)`
never exceeds ±0.999 and has no discontinuities. Worth being precise about what
that buys: measured against a linear reference, `tanh` adds *more* total
nonlinearity than a hard clip does, because it bends every sample rather than
only the few above 1.0. The argument for it is not the total — it is that the
distortion is smooth and spread rather than a discontinuity at the clip point,
and discontinuities are what "fuzzy" means to a listener. A look-ahead limiter
with real gain reduction beats both and is the right answer if this matters.

### A scream is not a loud voice

Gain gets the sentence heard across a car. It does not make it a shout, and the
distinction is the one ADR-0005 already draws about `Quiet`. Shouted speech is
Lombard speech: f0 up, spectral tilt flattened, energy moved into 1–4 kHz,
vowels lengthened. Gain alone reproduces none of that.

A tilt-plus-gain approximation is buildable on the same buffer and I built one,
but it is not yet good — my first recipe moved the spectral centroid the
**wrong way** (2789 → 2533 Hz) because the limiter's compression undid the lift.
It needs the tilt applied after limiting, or a proper multiband stage. Treat
"scream" as unproven; treat "loud enough to hear in a car" as solved by the two
paragraphs above.

The naming rule from ADR-0005 applies with full force. If what ships is gain,
call it loudness and put it on the volume control. A key labelled *Shout* that
produces a normal sentence at high volume is the same category of lie as a
*Whisper* that is only quiet.

## 4. The four withdrawn British voices — hypothesis confirmed

`neural_voice.dart` records that the British voices are withdrawn (§4.80), with
a "plausible cause and it is untested": sherpa's `lang` is left empty, so every
voice is fed `en-us` phonemes.

**The hypothesis is correct.** `lang=""` and `lang="en-us"` produce
byte-identical audio, so the empty default *is* American. And the fix needs a
specific string — the bundled espeak data has no bare `en-gb`:

| lang | result |
|---|---|
| `""` / `en-us` | 2.50 s — identical to each other |
| `en-gb` | **fails**: `Failed to set eSpeak-ng voice` |
| `en-gb-x-rp` | 2.69 s, phonemes differ |
| `en-gb-scotland` | 3.02 s |

`espeak-ng-data/voices` carries `en-GB-x-rp`, `en-GB-scotland`, `en-GB-x-gbclan`
and `en-GB-x-gbcwmd`, but no `en-gb`. So the one-line change is `lang:
'en-gb-x-rp'` for sids 7–10, and it genuinely re-phonemises all four:

| voice | sid | en-us | en-gb-x-rp |
|---|---|---|---|
| bf_emma | 7 | 2.50 s | 2.69 s |
| bf_isabella | 8 | 2.48 s | 2.67 s |
| bm_george | 9 | 2.76 s | 2.90 s |
| bm_lewis | 10 | 2.39 s | 2.63 s |

This is a phoneme-level confirmation, **not** a verdict that the voices are now
good. Whether RP phonemes make them shippable is a listening question, and the
comment in `neural_voice.dart` is right that they stay off until somebody has
heard them. But the guess it records is no longer a guess, and the change it
implies is one field on a config.

Note `lang` is per-engine in the sherpa config, not per-`generate` — carrying
British voices means building a second `OfflineTts` around the same model, or
rebuilding the config when the chosen voice crosses the accent line. The model
pointer can be shared; `kokoro.dart` already shares one by address.

## Order of work, by ratio

1. **Peak-normalise clips as they are stored.** Free loudness, no distortion,
   evens out composed phrases. Nothing to decide.
2. **Fix `tan(atan(v))`.** Dead line under a comment describing behaviour it
   does not have. Fix it whether or not gain is ever wired.
3. **Wire `gain` to a control**, once 1 and 2 are in. This is the requirement
   that motivated §4.5 in the first place.
4. **`lang: 'en-gb-x-rp'`** behind a listening check — four voices for one field.
5. **Terminal-rise post-process for `?`**, behind a listening check.
6. **Whisper by LPC resynthesis**, behind a listening check. Largest of these
   and the one most likely to come back uncanny.

Items 4–6 all end at the same gate, and `TONE-RESEARCH.md` is the reason to
respect it: measurements said calm moved correctly on every axis and a listener
said it was frightening.
