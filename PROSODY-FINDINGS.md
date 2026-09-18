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

### What makes a question sound like one: two cues, not one

Post-process the contour. The model's cooperation is not required, and a first
pass has been built and listened to. **A terminal rise alone is not enough** —
that was the first thing the listening check said. A question carries two cues
together:

1. **Terminal rise** across the final voiced syllable.
2. **Phrase-final lengthening.** A question does not only end higher, it dwells
   on the syllable it ends on. Leaving this out is what made a rise-only
   version read as clipped rather than interrogative.

Settings measured against each voice's own median f0 — how high the utterance
ends relative to that speaker's normal, six sentences, `af`:

| setting | end vs baseline | utterance duration |
|---|---|---|
| untreated `?` | −2.44 st | 1.00× |
| rise 5 st, lengthen 1.20 | −1.60 st | 1.06× |
| rise 8 st, lengthen 1.30 | +1.55 st | 1.10× |
| **rise 11 st, lengthen 1.40** | **+3.15 st** | **1.14×** |

The final syllable is found from the last contiguous voiced run rather than a
fixed tail, so the lengthening lands on the syllable rather than across a word
boundary. Utterance duration moves only 1.14× because the treatment applies to
the final syllable, not the sentence.

**Two implementations were rejected on the way, and both are worth recording.**

*Chunked pitch shifting.* Cut the tail into chunks, shift each by an increasing
amount, overlap-add. Each chunk leaves the phase vocoder with its own phase, so
overlapping chunks cancel and the measured contour moves *backwards*.

*Resampling with a varying read pointer.* Phase-coherent, and it moves the pitch
correctly — but it is a tape-speed change, so **the formants go up with the
pitch**. A listener called it "a robo chipmunk", which is exactly what a shifted
vocal tract sounds like. Restoring the envelope afterwards by LPC whitening and
re-imposing the source filter did not rescue it; the correction over-brightened.

**The method that works is TD-PSOLA.** Grains are two-period windowed slices
centred on glottal epochs, repositioned at new spacings and overlap-added.
Because a grain is never resampled, the vocal tract is unchanged *by
construction* — there is no formant correction to get wrong. It also delivers
more audible rise per nominal semitone, so the shipped setting is far gentler
than the resampling version needed: **3-5 st, not 11**. Spectral centroid in
the treated tail stays at or below the untreated value while f0 rises, which is
the measurement that says "no chipmunk".

It fits the architecture. A sentence ending `?` is already its own cache key —
`you want that?` and `you want that.` are separate entries — so the treated
clip is stored once and every later press is a cache read. Nothing on the tap
path changes, and the treatment is deterministic.

## 2. Whisper is reachable, and it is not the volume dial

ADR-0005 says a whisper is a different phonation rather than a quieter voice,
and declines to ship `Quiet` under a whisper's name. That is correct, and it is
now measured rather than asserted.

| variant | HNR | spectral centroid |
|---|---|---|
| normal | **3.07 dB** | 3267 Hz |
| `Quiet` (×0.25) | **3.07 dB** | 3267 Hz |
| phase randomisation | 0.78 dB | 4248 Hz |
| **LPC resynthesis** | **−7.29 dB** | 3971 Hz |

**`Quiet` has identical harmonicity and spectral shape to normal.** It is the
same phonation at a lower level, exactly as the ADR says — the table is the
receipt.

**Two methods were tried and only the second survives a listen.** STFT phase
randomisation devoices by about 2 dB and measures fine, but it was rejected on
hearing: independent random phase per bin per frame means overlapping frames
are mutually incoherent, and the ear reads that smearing as **several voices at
once** rather than one person whispering. The measurement had no way to see it.

The method that works is source-filter resynthesis:

- LPC analysis per frame (order 18 at 24 kHz) captures the formants.
- The excitation is **one continuous noise stream**, sampled at each frame's own
  time offset, so overlapping frames stay coherent — one voice, not a chorus.
  This is the whole of the difference.
- **Bandwidth expansion** — LPC coefficients scaled by `γ^k`, γ ≈ 0.90–0.94 —
  widens the formant bandwidths. This is the knob that reads as *breath* rather
  than as a buzzy filtered noise, and it is what a rise-only whisper lacks.
- Genuinely unvoiced frames are passed through unchanged, so `/s/`, `/ʃ/` and
  plosives keep their bite instead of being resynthesised into mush.

Devoicing improves from ~2 dB to ~10 dB against normal speech.

**And a fully devoiced whisper is the wrong target.** Clean, coherent and
correctly formanted, it was still called frightening. That is not a defect in
the synthesis: **a voice with no f0 at all is the one horror films use.**
Removing phonation entirely removes what marks a speaker as a living person,
and §5 non-negotiable 9's argument applies exactly — an AAC user is taken to
mean whatever came out, in whatever voice it came out in.

What is wanted is **breathy voice**, not whisper: the folds still vibrate with
turbulent noise alongside them. That is also what confidential human speech
mostly is — true whisper is rarer than people assume. The knob is how much
phonation survives:

| retained voice | HNR | centroid |
|---|---|---|
| normal | 3.07 dB | 3264 Hz |
| 0% (full whisper) | -7.13 dB | 4295 Hz |
| 30% | -6.53 dB | 4280 Hz |
| 45% | -4.23 dB | 4183 Hz |
| 60% | -1.34 dB | 4016 Hz |

Breath is present across the whole range — the centroid stays 750-1000 Hz above
normal at every setting. Only the pitch comes back. **The setting is a listening
choice, not a measurement**, which is why it ships as a ladder.

The absolute HNR figures are a normalised-autocorrelation proxy rather than a
proper cepstral HNR — read the contrast, not the levels.

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
5. **Question contour for `?`** — terminal rise *and* final lengthening, by
   TD-PSOLA, at roughly 3-5 st / 1.30×. Prototyped and heard twice; tuning,
   not discovery. Resampling is a dead end — it chipmunks.
6. **Breathy voice, not whisper** — LPC resynthesis with bandwidth expansion,
   mixed back over retained phonation. Prototyped and heard twice. Full
   devoicing is a dead end: it is clean, and it frightens people.

Items 4–6 all end at the same gate, and `TONE-RESEARCH.md` is the reason to
respect it: measurements said calm moved correctly on every axis and a listener
said it was frightening.
