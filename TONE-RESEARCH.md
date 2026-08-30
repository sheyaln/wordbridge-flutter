# Tone research — where sad, stern and sarcastic actually stand

Continues gate 3 in REQUIREMENTS.md §4.5. Everything here is StyleTTS 2
(LibriTTS checkpoint), which ships the style encoder Kokoro omits.

## The method that works: emotion as a direction

Taking a tone from one actor's clip changes who the voice sounds like. Taking
the **paired difference averaged over 24 actors** should cancel the speaker and
leave the emotion:

```
d[emo] = mean over actors of ( style(actor, emo) − style(actor, neutral) )
tone   = base_voice + k · d[emo]
```

Run with `alpha=0, beta=0`, which uses `ref_s` directly and **skips the
diffusion sampler entirely — so it is deterministic.** That matters beyond this
experiment: a cached word has to be byte-identical every time it is spoken, and
this is how you get that from a model that is stochastic by default.

### It fixed the defect that looked fundamental

Gate 3 reported that tempo does not transfer — duration flat at 1.77–2.10 s
across every emotion. With directions it moves properly:

| | dur | f0 | f0 sd | tilt | rms | timbre drift |
|---|---|---|---|---|---|---|
| neutral | 1.85 | 223.0 | 22.3 | 0.619 | 0.0032 | — |
| **calm k=1** | 2.17 | 219.0 | 20.4 | 0.650 | 0.0028 | **19.3** |
| **calm k=2** | **2.65** | 217.6 | 21.1 | 0.790 | **0.0022** | **41.2** |
| angry k=1 | 1.92 | 322.8 | 38.2 | 0.832 | 0.0530 | 288.4 |
| angry k=2 | 2.10 | 310.9 | 74.4 | 1.099 | 0.1149 | 418.4 |
| sad k=1 | 2.07 | **270.1** | 34.4 | 0.535 | 0.0082 | 81.7 |
| sad k=2 | 2.27 | **322.2** | 50.2 | 0.615 | 0.0143 | 143.5 |

**Calm is the first genuinely shippable candidate.** Slower (1.85 → 2.65 s),
pitch unchanged, spread unchanged, quieter, and the smallest timbre change of
anything tested. Every axis reads as calm and nothing else moved.

**Angry/stern is robust** — energy up 16×, spectral tilt up, pitch spread up,
consistently at both strengths.

**Sad is still inverted.** Pitch goes *up* — 223 → 270 → 322. Two independent
methods now say the same thing, so it is a real finding, not a bad run.

## Why sad fails: the corpus, not the method

Every direction was pushing the same way. Measuring how much each shares with
the others' mean:

| direction | cosine to the shared component |
|---|---|
| happy | **+0.938** |
| angry | **+0.934** |
| sad | **+0.908** |
| disgust | +0.833 |
| calm | +0.229 |

**Sad, happy, angry and disgust are 83–94% the same direction.** In RAVDESS
they barely separate at all. That is what an *acted* corpus does: actors at
"strong intensity" perform arousal, so acted sadness is loud and high, and real
sadness is quiet and low. Calm is the outlier at +0.23 — the one emotion that
is not performed by pushing harder, which is exactly why calm is the one that
worked.

### Removing the shared component recovers sad's direction, and breaks the voice

| | dur | f0 | f0 sd | tilt | rms |
|---|---|---|---|---|---|
| neutral | 1.85 | 223.0 | 22.3 | 0.619 | 0.0032 |
| sad-specific k=1.5 | 1.85 | **214.9** | **20.1** | **0.061** | 0.0099 |
| sad-specific k=3.0 | 1.82 | **212.8** | 19.9 | **0.027** | 0.0235 |
| calm-specific k=3.0 | 1.97 | 112.6 | **4.7** | 0.032 | 0.0234 |

Pitch finally moves the right way. But spectral tilt collapses from 0.619 to
0.03 — a dead, muffled voice — and calm at k=3 goes to a 4.7 Hz spread, which
is a monotone. The residual is a small noisy vector being scaled up until it
leaves the distribution the model was trained on.

**So this is not a tuning problem and more arithmetic on RAVDESS will not fix
it.** The information needed to separate sadness from arousal is not in the
corpus.

## Where that leaves the three tones

| | State | What it needs |
|---|---|---|
| **Calm** | **Works now** | A listening check, then it can ship |
| **Stern** | Close | It is restrained anger; the arousal direction is solid. Needs the strength calibrated and a listening check |
| **Sad** | Blocked on data | A corpus of natural or elicited sadness, not acted |
| **Sarcastic** | Not attempted | See below |

### What the metric could not tell us

"Timbre drift" here is MFCC distance, and it **cannot separate "sounds angry"
from "sounds like someone else"** — an angrier voice genuinely has a different
spectrum. Angry's drift of 288 is partly the emotion working. Answering the
speaker-leak question properly needs a speaker-verification embedding, not
MFCCs. Do not read these drift numbers as a leak measurement.

### Sarcasm

Still not attempted, and the framing matters: the literature's F1 62.5 ceiling
is for *detecting* sarcasm from prosody plus semantics. We are *producing* it,
and **the user supplies the semantics** — they know they are being sarcastic.
So the question shrinks to whether listeners reliably hear a given contour as
sarcastic, which is a listening test with real people, not an acoustic metric.
The one published cue is loudness, which we fully control.

## Next, in order

1. **A listening check on calm and stern.** They are the two that survived
   measurement. Nothing more should be built on them until somebody has heard
   them next to neutral and said which is which.
2. **A non-acted corpus for sad**, or drop sad. Options are elicited/natural
   emotional speech, or the architecture below.
3. **Same-speaker references.** If the voice and the tone references are the
   same person — a donor recording the same sentences neutrally, sadly,
   sternly — there is nothing to disentangle and no corpus licence question,
   because the audio was given for this purpose. It is a much larger product
   (recording flows, consent, storage, per-voice tone sets) and it is the only
   route that solves all three tones cleanly.
