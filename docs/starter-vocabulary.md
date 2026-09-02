# Starter vocabulary: the derivation

`app/lib/db/seed/core_vocabulary.dart` opens with "Independently designed" and
cites this file. This is what that claim rests on: where every part of the
shipped word list came from, what was verified, what was not, and what is
judgment wearing no citation.

Read it as a provenance record. Every published source the vocabulary draws on
is named below with a DOI or a URL, so every claim here can be checked against
the source rather than taken on trust. Every word that came from somewhere
other than a published source is accounted for in §2.5 as judgment.

Counts are measured at commit `28fb67a`. Levels are code and they move; the
counting rule in §5 is the durable part.

---

## 1. What ships

**The unit is a grid location, not a word.** One seed item is one location. The
count is over `homeBands` + `pinnedQuestions` + `categoryBands` in
`core_vocabulary.dart`, which is how `vocab_level_calibration_test.dart` counts.

At `28fb67a`: **377 locations, 371 distinct labels.** Six labels hold a
location on two different boards (`like`, `doctor`, `nurse`, `thirsty`, `bike`,
`outside`), which is a standing decision, not a defect (REQUIREMENTS §5.1). One
label twice on *one* board would be a defect.

Of the 377 locations, 369 speak a word. The other eight are grammar keys
(`+s`, `+ed`, `+ing`, `+'s`, `am/is/are`, `was/were`, `a`, `the`). No location
carries punctuation: `?` is an utterance bar action, not a board button.

### Per board, per level

Cumulative: a level 2 board draws its level 1 words too.

| Board | Level 1 | ≤ Level 2 | ≤ Level 3 |
|---|---|---|---|
| root board, content area | 37 | 67 | 67 |
| pinned question column | 6 | 6 | 6 |
| people | 6 | 25 | 33 |
| food | 10 | 28 | 52 |
| play | 8 | 23 | 44 |
| feelings | 14 | 31 | 47 |
| places | 5 | 15 | 33 |
| body | 8 | 31 | 47 |
| doing | 6 | 26 | 48 |
| **total** | **100** | **252** | **377** |

The pinned column is the same six locations on every board, so it is not any
one board's own load.

Nothing on the root board is level 3, which is why its ≤ 2 and ≤ 3 columns are
equal. The tail of the verb band is drawn at level 2 and paged off like level 3
through `pageRank`, so it is revealed early and still sheds first on a grid too
narrow to hold it.

### Why one total is the wrong number

The age presets append vocabulary on top of the figures above, so there are
four answers, not one:

| Preset | Starting level | ≤ 1 | ≤ 2 | ≤ 3 |
|---|---|---|---|---|
| Under 6 | 1 | 100 | 252 | 377 |
| 6 to 12 | 2 | 100 | 252 | 377 |
| 13 to 17 | 2 | 109 | 273 | 404 |
| 18 and over | 2 | 112 | 281 | 408 |

And a fifth, because the strong language band (seven locations, all level 2) is
appended to the `feelings` board for the teen and adult presets whether or not
the toggle is on, hidden in place rather than omitted. Counting it: teen
109 / 280 / 411, adult 112 / 288 / 415.

REQUIREMENTS §4.11 is why no total appears in the setup copy. What holds across
every preset at every geometry is the **density**: never more than 36 drawn on
one page at level 1 on a category board, and never more than 37 on the root
board, asserted for all seven tested grid geometries and all four presets in
`vocab_level_calibration_test.dart`. The root board's extra one is `maybe`;
§2.5 is why it is there and why nothing else has been let in beside it.

---

## 2. Where the words came from

Every word in the shipped vocabulary comes from one of two places: the
published list in §2.1, or the judgment recorded in §2.5. Those are the only
two sources. No list was reconstructed from memory, inferred from an abstract,
or copied from a secondary summary of a paper that was not read.

### 2.1 Verified from the primary source, and used

**Project Core, Universal Core 36.** Center for Literacy and Disability
Studies, UNC-Chapel Hill, via <https://project-core.com>.

The 36 words are recorded in this repo as `universalCore36` in
`app/test/core_board_set_test.dart` and pinned by two tests: every one must be
in the shipped vocabulary, and every one must be *drawn* at level 1 rather than
seeded and held back.

Measured at `28fb67a`, the level 1 root board is **exactly** the Universal Core
36 plus seven named additions and nothing else:

| | Count |
|---|---|
| Universal Core words in the root content area | 31 |
| Universal Core words in the pinned question column (`what where who when why`) | 5 |
| Additions in the content area (`yes no don't wait me maybe`) | 6 |
| Addition in the pinned column (`how`) | 1 |
| **Root board at level 1** | **43 locations, 37 of them content** |

A ceiling of 36 content locations is not invented here. Project Core publishes
the *same* 36 words at 4, 6, 9 and 36 locations per page, verified on
<https://project-core.com/communication-systems/>, which also lists a variant
spread over two pages at 36 locations, and a classroom poster. The vocabulary
is held constant and only pagination follows access method. That published
ladder is the direct evidence for a per page ceiling, and for the decision that
a grid too small to draw all 36 at once **pages the rest rather than dropping
it**.

**Hattingh & Tönsing (2020).** *The core vocabulary of South African
Afrikaans-speaking Grade R learners without disabilities.* South African
Journal of Communication Disorders 67(1), a701. DOI
[10.4102/sajcd.v67i1.701](https://doi.org/10.4102/sajcd.v67i1.701),
[PMC7433287](https://pmc.ncbi.nlm.nih.gov/articles/PMC7433287/).

Read in full text. It sets the level 2 band and nothing else. Two things worth
stating precisely, because the shorthand elsewhere in this repo compresses
them:

- The figure used, 200 to 250 spoken words accounting for roughly 80% of a
  person's spoken communication, is this paper **reporting prior work in
  English and other European languages**, not its own result.
- Its own result is 239 Afrikaans core words covering 79.4% of the composite
  speech sample. Afrikaans, Grade R, without disabilities.

So the level 2 band (`inInclusiveRange(200, 265)` in
`vocab_level_calibration_test.dart`) rests on a reported convergent figure, not
on a measurement in this population. It sets a **size**, and no word in this
repo was taken from it.

**Laubscher & Light (2020).** *Core vocabulary lists for young children and
considerations for early language development: a narrative review.*
Augmentative and Alternative Communication 36(1):43-53. DOI
[10.1080/07434618.2020.1737964](https://doi.org/10.1080/07434618.2020.1737964).

Abstract verified verbatim (Semantic Scholar; the publisher page returns 403).
The sentence this rests on: results "suggest that core word lists may
under-emphasize many of the types of words that predominate in early expressive
vocabulary; these lists may not be the most appropriate resources to guide AAC
system design and instruction for early symbolic communicators."

Used as a **bias, not a list**. It is the argument for level 1 being heavier on
concrete nouns and social words than the Universal Core 36 alone would make it,
which is why `toilet`, `emergency`, `hurt`, `too loud` and `I need a break` are
level 1 and `biscuit` is not. It supplies no words of its own.

**Light, Wilkinson, Thiessen, Beukelman & Fager (2019).** *Designing effective
AAC displays for individuals with developmental or acquired disabilities: state
of the science and future research directions.* Augmentative and Alternative
Communication 35(1):42-55.
[PMC6436972](https://pmc.ncbi.nlm.nih.gov/articles/PMC6436972/).

Read in full text. It establishes that array size and navigation depth both
cost accuracy and latency. It gives **no threshold** and recommends no maximum
number of symbols per display. It is the reason a per page ceiling exists at
all; Project Core's published densities are the reason it is 36, and the reason
the one board that exceeds it exceeds it by one.

### 2.2 Real, unobtained, and therefore unused

These two papers are frequently cited as sources of a beginning AAC vocabulary.
Their DOIs are confirmed via Crossref. **Their word lists sit behind a paywall
and were never obtained, and nothing in the shipped vocabulary rests on
either.**

| Citation | Verified how | Status |
|---|---|---|
| Banajee, DiCarlo & Buras Stricklin (2003). *Core vocabulary determination for toddlers.* AAC 19(2):67-73. DOI [10.1080/0743461031000112034](https://doi.org/10.1080/0743461031000112034) | Crossref bibliographic lookup | Real. List not obtained. **Unused.** |
| Marvin, Beukelman & Bilyeu (1994). *Vocabulary-use patterns in preschool children: effects of context and time sampling.* AAC 10(4):224-236. DOI [10.1080/07434619412331276930](https://doi.org/10.1080/07434619412331276930) | Crossref bibliographic lookup | Real. List not obtained. **Unused.** |

This distinction is the most important thing this document records. A plausible
word list attributed to a study nobody read is indistinguishable from a
fabrication, which is why the status column exists and why it says **unused**.

### 2.3 Named, correctly described, and not used as a source of words

**Boenisch & Soto (2015).** *The oral core vocabulary of typically developing
English-speaking school-aged children: implications for AAC practice.*
Augmentative and Alternative Communication 31(1):77-84. DOI
[10.3109/07434618.2014.1001521](https://doi.org/10.3109/07434618.2014.1001521).

Title verified via Crossref. The population is **typically developing**, which
makes it a proxy for AAC users rather than a sample of them. REQUIREMENTS §4.13
records the same reading. No word in this vocabulary was taken from it.

**Thistle & Wilkinson (2013).** *Working memory demands of aided augmentative
and alternative communication for individuals with developmental disabilities.*
Augmentative and Alternative Communication 29(3):235-245. DOI
[10.3109/07434618.2013.815800](https://doi.org/10.3109/07434618.2013.815800).

Title, journal, volume, issue and pages verified via Crossref. It is a
**theoretical review** of working memory load, and it **contains no number**
for how many symbols a display should carry. The per page ceiling comes from
Project Core's published densities (§2.1), and this paper is not cited for it
anywhere in the code.

### 2.4 Ordering, not selection

Words are ordered left to right across the root board in Fitzgerald Key order,
who then does then what then where, so reading the board builds a sentence.
What is used is the order of the word classes, which is an idea rather than an
expression.

**1926 is confirmed.** Edith Mansford Fitzgerald (1877 to 1940) published
*Straight Language for the Deaf: A System of Instruction for Deaf Children* in
1926, which is the basis for calling the key out of copyright. Two independent
published sources give that year:

| Source | What it says | Read how |
|---|---|---|
| Robert F. Panara, *The Deaf Writer in America from Colonial Times to 1970, Part II* (1970), opening page. Panara was professor of English and chairman of the NTID English department at RIT | "her book, *Straight Language for the Deaf* (1926), which ran through two editions and constitutes an attempt to simplify the teaching of correct sentence structure" | Scanned page read in full, via the Internet Archive Wayback copy of RIT's repository PDF |
| Julie L. Lautenschlager, "Edith Mansford Fitzgerald (1877–1940)", *Dictionary of Virginia Biography*, Library of Virginia, published 2016 | "resulted in the publication of her groundbreaking book, *Straight Language for the Deaf: A System of Instruction for Deaf Children* (1926). First published locally, the book went through numerous editions" | Entry read in full at lva.virginia.gov |

No library catalog holds a 1926 imprint, and that is the expected result rather
than a contradiction: the Dictionary of Virginia Biography says the first
edition was **published locally**, which is why it never entered the national
record. What the catalogs do hold is consistent with a first edition well
before 1949. The Library of Congress has a single record, the **4th ed.**
(Volta Bureau, 1949, LCCN 49004933, OCLC 1901325), whose author heading gives
Fitzgerald's dates as 1877 to 1940, so a fourth edition in 1949 is posthumous
and the first cannot be it. HathiTrust's record for the 9th ed. (1962) notes a
preface dated 15 February 1937.

Searched and found nothing earlier: Library of Congress (SRU catalog),
HathiTrust Bib API, Open Library, Internet Archive, Harvard LibraryCloud.
Blocked outright and therefore unchecked: the HathiTrust web catalog and its
page scans, WorldCat, and Jisc Library Hub. The one source that would settle it
from the book itself is the copyright page of a scanned edition, which would
list the earlier copyright years, and it sits behind that block. HathiTrust's
own rights determination on both the 1949 and 1962 scans is public domain.

Panara and the *Dictionary of Virginia Biography* disagree on how many editions
followed, "two" against "numerous", with the Library of Congress showing a 4th
by 1949 and a 9th by 1962. Only the 1926 date carries any weight here, and on
that they agree.

The copyright position: a work first published in the United States in 1926
entered the US public domain on 1 January 2022, and Fitzgerald's death in 1940
puts it out of copyright in life plus 70 jurisdictions since 2011. The
dependency is smaller than either date anyway. What is used is a word class
order, which is an idea and was never copyrightable.

### 2.5 Ours, with no citation behind it

Of 371 distinct labels, **36 come from a published list.** The other **335 are
judgment.** They are not evidence and this document does not present them as
evidence.

The seven root board additions are spelled out rather than counted, because
adding to that set is adding to a beginning communicator's first board. The
reasoning, from `core_vocabulary.dart` and REQUIREMENTS §4.11:

| Word | Why the Universal Core 36 does not cover it |
|---|---|
| `yes` | The list carries `not`, which negates inside a sentence. Nothing on it answers a question. |
| `no` | Same. `not` cannot answer a direct question; a board that can only agree is not a communication device. |
| `don't` | `not` cannot make an imperative. Without `don't` the board says "I not go" where the user meant "don't go", and the imperative is the one that stops something happening. |
| `wait` | Floor holding. An AAC user composes slower than a speaker talks; this is the one tap way to stop being talked over. |
| `me` | The possessive key fires after `I` and produces "I's". The object pronoun on the `people` board is two movements from "help me". `me` is the one object pronoun level 1 keeps, because it is the one that follows a verb. |
| `how` | The one English question word the list omits. It sits in the pinned column with the other five, which would otherwise offer five of the six and read as having a hole. |
| `maybe` | The list can agree and, with `yes`/`no` above, refuse. It has no hedge. Without one, every answer to a direct question is a commitment, the person is made to overstate what they mean each time, and nobody around them can tell it is the board talking rather than them. |

`?` is not on any board. It is an utterance bar action, so a question can be
punctuated from wherever the sentence was built rather than costing a location
on every board that carries the pinned column.

Everything on the seven category boards, all of the level 2 and level 3
vocabulary, the age preset extras and the strong language band are the same
kind of judgment. The arguments are in the code comments beside the words: that
a board which can only say "happy" and "sad" cannot report pain, that needing
the toilet is the most frequent daily request a user has, that an adult who
cannot say "medication" depends on somebody else's guess about their own body.
Those are reasons. They are not citations, and the distinction is deliberate.

One design rule belongs with them, because it constrains what a word may be
asked to do. Every button carries exactly one meaning regardless of what
preceded it (ADR 0002, which lives with the project rather than in this repo),
so no word in this vocabulary depends on a sequence to mean what it says.

Three further citations appear in `band_layout.dart` and `core_vocabulary.dart`:
Thistle & Wilkinson (2017), Wilkinson, Gilmore & Qian (2022), and Fallon, Light
& Achenbach (2003). They bear on how words are *arranged* on a board, not on
which words are in the vocabulary, so they are out of scope here and were not
verified in this pass. If a claim about arrangement ever needs defending, they
need the same treatment §2 gives the rest.

---

## 3. License position

**Unresolved, and it should be resolved in writing before a public release.**

| Source | States | Verified |
|---|---|---|
| <https://project-core.com> (site footer, and `/communication-systems/`) | CC BY-SA 4.0 | Yes, 2026-08-29 |
| med.unc.edu | CC BY 4.0, per [NOTICE.md](../NOTICE.md) | **No.** Not reproduced in this pass |

The CLDS landing page at `med.unc.edu/healthsciences/clds/` names Project Core
and the Universal Core vocabulary but states no license; it links out to
project-core.com. Candidate CLDS Project Core URLs returned 403 or 404. So half
of the discrepancy NOTICE.md records is confirmed and half is not, which is
itself worth writing down: the CC BY 4.0 reading may be stale, may be on a page
that has moved, or may never have said that.

Both licenses permit this use. They differ in what they oblige:

- **CC BY 4.0**: attribution only.
- **CC BY-SA 4.0**: attribution plus ShareAlike on derivative content.

Do not pick one silently. What CLDS should be asked to confirm in writing:

1. Which license governs the Universal Core 36 **as a word list**, as distinct
   from the printed board files.
2. If ShareAlike applies, whether it attaches to the word list alone or to a
   larger vocabulary that contains it. That is the practical question, since
   335 of 371 labels here are not theirs.
3. That attribution as given in [NOTICE.md](../NOTICE.md) is what they want.

Until then: the attribution stands, the discrepancy stays flagged in NOTICE.md,
and neither reading is asserted as settled.

wordbridge's own code is MIT. That license does not extend to vocabulary or
symbol content.

---

## 4. Symbols are a separate question

Pictures on buttons are licensed independently of the words on them. One
bundled pack ships, `core`, assembled through Global Symbols from Mulberry
Symbols, Stellar Symbols, Tawasol Symbols and OpenMoji, all CC BY-SA 4.0, with
per symbol credits carried in its manifest. ARASAAC is CC BY-NC-SA and
are never bundled; `tools/check_symbol_boundary.sh` keeps application code off
concrete packs so that a commercial fork can drop them. The full position is in
[NOTICE.md](../NOTICE.md) and [symbol-packs.md](symbol-packs.md) and is not
repeated here.

---

## 5. Recounting

Every figure above counts seed items, one item per grid location, over
`homeBands`, `pinnedQuestions` and `categoryBands` in
`app/lib/db/seed/core_vocabulary.dart`, filtered by `level <= n`. Preset figures
add `AgeBand.extrasFor(category)` across `categoryNames`; the strong language
figures add `swearingBand.items`, which `categoryBandsFor` appends to
`feelings` when `AgeBand.canSwear`.

`vocab_level_calibration_test.dart` counts the same way and asserts the bands
rather than the exact totals, deliberately: an exact number in a test gets
edited to match the code instead of argued with. The counts here are a snapshot
of `28fb67a`; the counting rule is what does not go stale.
