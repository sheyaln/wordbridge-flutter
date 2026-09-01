# ADR 0002: One symbol, one meaning

**Status:** Accepted
**Date:** August 24, 2026

## Context

*Iconic encoding* is a well established approach in AAC: a small set of
multi meaning, or *polysemous*, icons whose meaning depends on the sequence
they are pressed in. A picture of an apple might participate in `eat`, `food`,
`red` and `teacher` depending on what follows it. The claimed benefit is a
large vocabulary from few keys, with short and fixed motor sequences.

Two independent reasons to reject it for wordbridge.

**Domain preference.** The practitioner who prompted this project dislikes
polysemous encoding outright. That is first hand judgment from someone who
teaches AAC users daily, and it outweighs a design argument made from a
distance.

**Evidence.** Light et al. (2004), *Augmentative and Alternative Communication*
20(2), studied 80 typically developing children aged four and five across four
vocabulary organizations. Children performed **significantly worse with iconic
encoding** than with taxonomic grids, schematic grids, or schematic scenes, at
both ages, in both learning and generalization. Light et al.'s 2019 review of
the state of the science in AAC display design does not discuss iconic encoding
at all. The acknowledged limitation of the approach is that the user must
memorize the codes, and the icons are not transparent, so they have to be
taught.

The cross cultural picture is worse. Icon to meaning associations of this kind
rest on English language metaphor and idiom. wordbridge intends to work in more
than one language, and an encoding scheme whose semantics are culturally load
bearing is hostile to that.

## Decision

**Every button carries exactly one meaning.** A symbol means the same thing
regardless of what was pressed before it. Vocabulary beyond the root board is
reached by navigating into named category boards, not by composing icon
sequences.

Motor planning still holds, arguably more cleanly. A word's motor path is a
fixed sequence of *locations* (`home`, then `food`, then `apple`), which is
stable, learnable and inspectable. What it is not is a sequence of
reinterpretations.

## Consequences

**Good**

- Simpler mental model for AAC users, families and communication partners.
  Nobody has to be taught what an icon "means in this context."
- Simpler to teach and to model, which matters because aided language
  stimulation by a partner is the most recommended AAC intervention practice.
- Translation becomes tractable. A label and a spoken string per locale, with
  no metaphor layer to relocalize.
- The `buttons` schema needs no sequence state machine: one row, one `label`,
  one `message`. Navigation is an `action`, not a semantic operator.
- Maps cleanly onto Open Board Format, which models buttons as single meaning
  with an optional `load_board`.

**Costs, accepted**

- More boards, and more navigation depth for the same vocabulary size than a
  sequence encoding needs. Mitigated by **returning to the root board after any
  speaking selection**, which keeps most words at two or three taps. That is
  the highest value, lowest cost motor planning feature available to us.
- Lower vocabulary density per key. Accepted.

## Related

- [ADR 0001](0001-project-thesis.md), the project thesis
- [ADR 0003](0003-motor-plan-model.md), position is identity
- [Symbol packs](../symbol-packs.md), the symbol sets and how they are kept
  swappable
