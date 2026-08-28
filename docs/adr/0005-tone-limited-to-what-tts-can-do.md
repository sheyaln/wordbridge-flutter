# ADR-0005: Ship only the tones platform speech can honestly produce

**Status:** Accepted
**Date:** 2026-08-28

## Context

The requirement asked for configurable voices, tone presets including *calm*, *urgent*, *joking* and *sarcastic*, and an in-app volume where "maximum is a yell, minimum audible is a whisper".

`flutter_tts` — and the iOS and Android engines beneath it — expose three parameters: rate, pitch, volume. There is no contour control, no breathiness, no emphasis marking, and no gain stage above the device's own volume.

So some of what was asked for is buildable and some of it is not, and the decision is what to do about the gap.

The tempting answer is to ship the full list and approximate: call a low-volume low-pitch voice "whisper", call a fast clipped voice "sarcastic", and let users judge. Every one of those presets would be *something*, and the labels would match the requirement.

## Decision

**Ship four tones — Normal, Calm, Urgent, Quiet — and no others.** Each is built from rate, pitch and volume, and each does what its name says.

**Name the fourth one for what it is.** It is called *Quiet*, not *Whisper*, because it is the same voice turned down. A whisper is a different phonation, not a quieter one.

**Do not ship *sarcastic* or *joking* at all.** Sarcasm is carried almost entirely by prosodic contour, which is the one thing platform TTS will not let an app specify. A "sarcastic" preset that merely changed speed would be a label attached to nothing.

**Say so in the app, not only here.** The voice screen carries the explanation where the caregiver is standing when they wonder why the list is short.

### Why the honesty is load-bearing rather than fastidious

An AAC user is taken to mean whatever came out of the speaker. If they select "sarcastic" and the device produces a flat sentence, they have not made a joke that landed badly — they have said a sincere thing they did not mean, to someone who has no reason to doubt it, and they usually cannot issue a correction fast enough to matter.

For a hearing user with speech, a TTS preset that misses is a mild annoyance they talk over. For this user it is a misattributed statement. **The cost of a wrong preset is not borne by the person who chose it.** That asymmetry is the whole argument, and it is why "ship it and let them judge" is the wrong instinct here specifically.

The same reasoning already governs symbols (ADR-0002, and the exact-match rule for unattended attachment): never assert something on the user's behalf that might be wrong, when a plainer honest output is available. Tone is that rule applied to sound.

## The volume gap, stated plainly

**The loudness requirement is not met, and it is the most-wanted half.** The complaint that motivated it is specific and repeated:

> "My son will be in the backseat of the car with his iPad and all of this motor planning is useless if I cannot hear him… I don't want my son to whisper, I want him to talk."

In-app volume is a *fraction* of the device's own volume. It can go down and it cannot go up past what the hardware is set to. The voice screen says this rather than implying the slider goes further than it does.

Closing it properly means `synthesizeToFile` plus playback through an audio graph with gain. That inserts a file write and a player start between a tap and a word, which §5 forbids outright — nothing stands between a user and speech. A worse voice that arrives instantly beats a louder one that arrives late.

So the gap stays open, named, and pointed at §4.5.

## Consequences

Tone is a per-profile setting rather than something the user changes mid-sentence. Making it reachable in the moment would cost a grid cell, and cells are the scarcest thing on the board — the mechanism for a caregiver to spend one on it deliberately is a later decision, not a default.

The four tones will look thin next to a competitor listing a dozen. That comparison is worth losing.

**What unlocks the rest.** A bundled on-device neural voice (§4.5) gives genuine prosody, genuine breathiness, gain that is ours to set, and a voice that does not sound like every other AAC user's — which autistic adults name directly as disempowering. `SpeechEngine` stays engine-agnostic so that arrives as a swap. Until it does, this list is what is true.
