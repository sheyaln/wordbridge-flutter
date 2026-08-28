# ADR-0004: Word prediction that suggests without rearranging

**Status:** Accepted
**Date:** 2026-08-28

## Context

Word prediction is the single most requested convenience in text entry and the single most dangerous feature to add to a motor-planning AAC board. The obvious implementation — surface the likely words where the finger already is — destroys the thing the rest of this project exists to protect.

This is documented, not speculative. Dana Nieder, writing in 2014 about her daughter's AAC use, names predictive reordering directly as a motor-planning killer, and AssistiveWare's own guidance warns against dynamic rearrangement for the same reason. A board whose contents depend on what was said a moment ago cannot be automated, because there is no stable "same physical spot" to automate.

The counter-argument for having it at all is real: a nonspeaking user producing a sentence one deliberate tap at a time is slow, and every saved tap is a saved second in a conversation that will not wait for them.

So the question is not *whether* to predict, but where the predictions may live and what they are allowed to cost.

## Decision

**Predictions get their own strip and never touch the board.** No cell's contents, position, or ordering depends on prediction state. The strip sits between the sentence and the grid, and the grid below it is exactly the grid that was there before.

**The strip costs grid height, and that is stated rather than hidden.** It is a fixed band, so with it on every button is a little shorter. That is a change to where things are — the same category of change as resizing the grid — and it is therefore off by default and presented with its cost. It is also the *cheapest* such change available, because turning it off restores the previous layout exactly: no vocabulary is rebuilt, no cell is touched, nothing is migrated. It is the one layout change that is free to undo.

**Six rules make the strip itself safe to reach for.**

1. **Only words already on this user's boards.** A suggestion is a shortcut to a button, never a source of new vocabulary. Words a caregiver has hidden, or held back by level, are never offered — otherwise the strip routes around a decision somebody made and `vocab_level` stops meaning anything.
2. **Fixed slots.** The width divides evenly into a constant number of places and words are drawn inside their slot. Chips sized to their text would put the third suggestion somewhere different depending on how long the first two words were.
3. **It settles.** Contents change after every word, so the strip ignores taps for the same delay the boards use. Without it, a finger already descending when the suggestions update lands on a word nobody chose — which is the exact failure the board-level settle delay exists to prevent.
4. **An empty slot is a hole, not a button.** It takes no tap and speaks nothing, for the same reason a masked cell does not.
5. **Deterministic order.** Equal counts break alphabetically. Two identical states must produce the same strip in the same order, or the strip is an unstable target by construction.
6. **Suggestion taps are logged as `prediction`, not `touch`.** The remap warning counts how often a *location* was reached for; a word taken from the strip was not reached for at all.

That last rule needed a change beyond prediction itself. `historyForCell` and the grid-rebuild impact count now take an **allowlist** of sources that mean the user physically went to the location — `touch` and `switchAccess` — rather than a list of exclusions. An allowlist means a source added later has to be considered before it can inflate a warning. The rebuild count was also counting partner modelling, which it should never have been.

**What is stored is counts, not a transcript.** `prediction_pairs` holds `(profile, previous_word, word, count)`. There is no timestamp, no ordering beyond the pair, and nothing recording that four words were one sentence. It is a deliberately weaker record than the usage log, because an AAC log is a complete transcript of a disabled person's private speech and prediction does not need one to work.

It is also **separate from the usage log**, which is consent-gated, exportable, and off by default. Prediction has its own store with its own lifecycle: it exists while prediction is on, and turning prediction off empties it. A caregiver can also clear it on its own, which is what the toggle cannot express — after a stretch where somebody else was holding the device, you want the suggestions reset without losing the feature.

**Learning happens when a sentence is spoken, not as each word is added.** What gets recorded is what the user chose to say. A sentence built and then cleared teaches nothing, and the intermediate states passed through on the way to a sentence are not sentences.

**Day one is not an empty strip.** With nothing learned, it reads the home board in the board's own order — which is not arbitrary, because columns there run in Fitzgerald sentence order and the leftmost hold the pronouns. The first suggestions are therefore `I`, `we`, `all`, `want`, `get`: the words sentences open with. Ranking by level and then alphabetically would have offered whatever happened to start with "a".

## Consequences

A user who turns prediction on pays a slightly shorter button for a shorter sentence, knows they are paying it, and can stop paying it at any time at no cost. A user who never turns it on is unaffected in every respect, including grid geometry.

The strip cannot make the board faster to learn, and it is not meant to — it is a shortcut for people who have already learned it, or a crutch for words they have not. Neither is a substitute for the motor plan, and neither is allowed to interfere with one forming.

**What this rules out.** Predictive reordering of grid cells, in any form, at any setting. Suggestions drawn from a general language model rather than this user's own history. Any prediction store that could reconstruct an utterance. Any of these would be a different decision, not a tuning of this one.

**Known limit.** Bigram counts are a weak model — they know what follows one word, not what follows a phrase, and they need a few dozen sentences before they beat the day-one fallback. That is an acceptable floor: it is honest about what it knows, it is cheap, it is offline, and its whole state is four columns anybody can read. A better model is a later decision that this one does not block.
