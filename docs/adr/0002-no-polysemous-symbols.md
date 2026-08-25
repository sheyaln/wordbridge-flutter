# ADR-0002: One symbol, one meaning — no polysemous icons

**Status:** Accepted
**Date:** 2026-08-24

## Context

LAMP inherits Minspeak's *semantic compaction*: a small set of multi-meaning ("polysemous") icons whose meaning depends on the sequence they're pressed in. A picture of an apple might participate in `eat`, `food`, `red`, and `teacher` depending on what follows it. The claimed benefit is a large vocabulary from few keys with short, fixed motor sequences.

Two independent reasons to reject it for wordbridge.

**Domain preference.** The practitioner who prompted this project dislikes polysemous encoding outright. That is first-hand judgement from someone who teaches AAC users daily, and it outweighs a design argument made from a distance.

**Evidence.** Light et al. (2004), *AAC* 20(2):63-88 — 80 typically developing four- and five-year-olds across four vocabulary organizations. Children performed **significantly worse with iconic encoding** (the Minspeak/Unity/LAMP family) than with taxonomic grids, schematic grids, or schematic scenes, at both ages, in both learning and generalization. Light et al.'s 2019 state-of-the-science review of AAC display design does not discuss iconic encoding at all. Meanwhile the Wikipedia-summarized canonical limitation holds: the user must memorize codes, and icons "are not immediately transparent [and] should be taught."

The cross-cultural picture is worse. Minspeak's icon-to-meaning associations rest on English-language metaphor and idiom. For a project whose clearest structural advantage over commercial vendors is multilingual support, an encoding scheme whose semantics are culturally load-bearing is actively hostile to the goal.

## Decision

**Every button carries exactly one meaning.** A symbol means the same thing regardless of what was pressed before it. Vocabulary beyond the root board is reached by navigating into named category boards, not by composing icon sequences.

Motor planning still holds — arguably more cleanly. A word's motor path is a fixed sequence of *locations* (`home → food → apple`), which is stable, learnable, and inspectable. What it is not is a sequence of *reinterpretations*.

## Consequences

**Good**

- Simpler mental model for AAC users, families, and communication partners. Nobody has to be taught what an icon "means in this context."
- Simpler to teach and to model, which matters because aided language stimulation by a partner is the most-recommended AAC intervention practice.
- Translation becomes tractable — a label and a spoken string per locale, with no metaphor layer to relocalize. Directly enables the multilingual strategy in [ADR-0007](0007-symbol-packs.md).
- The `buttons` schema needs no sequence-state machine: one row, one `label`, one `message`. Navigation is an `action`, not a semantic operator.
- Maps cleanly onto Open Board Format, which models buttons as single-meaning with an optional `load_board` — see [ADR-0009](0009-obf-interop.md).
- Sidesteps US9336198B2 (active to 2033, assignee PRC), which concerns navigating polysemous symbols across linked overlays with visual indicators. This is a side effect of the design choice, not the reason for it.

**Costs, accepted**

- More boards and more navigation depth than a semantic-compaction system needs for the same vocabulary size. Mitigated by **auto-return to the root board after any speaking selection**, which keeps most words at two or three taps — the highest-value, lowest-cost motor-planning feature available to us.
- Gives up the "4,000 words from 84 keys" density claim. We are not trying to match it.

## Related

- [ADR-0001](0001-project-thesis.md) — project thesis
- [ADR-0003](0003-motor-plan-model.md) — position is identity
