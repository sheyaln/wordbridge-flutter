# Notices and attribution

wordbridge's own source code is MIT licensed, see [LICENSE](LICENSE).

That license does **not** extend to the vocabulary and symbol content described
below. Read this before forking commercially.

---

## Vocabulary

**Universal Core 36**, Center for Literacy and Disability Studies, University
of North Carolina at Chapel Hill, via Project Core (<https://project-core.com>).

Used as the word *selection* for the shipped starter vocabulary. The layout is
independently designed; see [docs/starter-vocabulary.md](docs/starter-vocabulary.md),
which records every source the vocabulary draws on and how each level was
assigned.

> ⚠️ **Unresolved:** project-core.com states CC BY-SA 4.0 while
> med.unc.edu states CC BY 4.0 for the same list. Both permit our use, but
> BY-SA carries ShareAlike obligations on derivative content. Confirm with
> CLDS in writing before a public release.

---

## Symbol libraries

wordbridge never links a symbol pack directly; packs are loaded behind a
`SymbolPack` interface so they can be swapped or removed wholesale.

**A set is the unit, not a pack.** A pack is how pictures arrive — out of the
binary, off the network, out of the platform's own font. A set is whose
drawings they are, and it is what a caregiver switches on and off and what a
licence attaches to. One set can be served by two packs: Stellar and OpenMoji
pictures both ship inside `core` *and* are searchable through Global Symbols.
The set records live in `features/symbols/symbol_sets.dart`, referenced by both
packs, so one switch governs both halves.

### The sets, and where each one comes from

| Set | License | How it reaches the device | Commercial use |
|---|---|---|---|
| Stellar Symbols | CC BY-SA 4.0 | 111 pictures bundled in `core`, the rest fetched | yes |
| OpenMoji | CC BY-SA 4.0 | 153 pictures bundled in `core`, the rest fetched | yes |
| Device emoji | Unicode-3.0 (index only) | drawn by the platform's own font | yes |
| Mulberry Symbols | CC BY-SA 4.0 | fetched | yes |
| Mulberry Plus Collection | CC BY-SA 4.0 | fetched | yes |
| Mulberry Additional Symbols | CC BY-SA 4.0 | fetched | yes |
| Tawasol | CC BY-SA 4.0 | fetched | yes |
| ARASAAC | CC BY-NC-SA 4.0 | fetched, **off** until switched on | **no** |
| AAC Image Library | CC BY-NC-SA 4.0 | fetched, **off** until switched on | **no** |

Credits, in full:

| Set | Credit |
|---|---|
| Stellar Symbols | © Colin McNamee |
| OpenMoji | © OpenMoji Project. <https://openmoji.org> |
| Mulberry Symbols | © Garry Paxton 2008-2017, Steve Lee 2018-. <https://mulberrysymbols.org> |
| Mulberry Plus Collection | © Mulberry and Global Symbols. <https://globalsymbols.com> |
| Mulberry Additional Symbols | © Verlag Karin Kestner GmbH. <https://www.kestner.de> |
| Tawasol | © Mada, Qatar. <http://tawasolsymbols.org> |
| AAC Image Library | © AAC Image Library. <https://aacil.neocities.org> |

**Every one of these is credited inside the running app**, on the Symbol
credits screen, which lists the sets that are switched on rather than the packs
whose images ship. That distinction is the licence: the six fetched sets ship
no manifest, so a screen that read manifests credited them nowhere at all while
a caregiver could search them, pick one and put it on a board.

A set that is switched off is not credited, and does not need to be. The
registry refuses to resolve it — for a fetched file already on the device and
for a bundled picture alike — so nothing of it is appearing anywhere.

### Bundled, commercial use permitted

**One pack ships: `core`.** It is a single set of 275 pictures assembled from
the sources below via Global Symbols, and its manifest carries the credit for
each picture individually. The sources are **not** shipped as packs of their
own. This app does not carry Mulberry, or OpenMoji, or any of them, in full.

| Source of a `core` picture | License | Notes |
|---|---|---|
| Mulberry Symbols | CC BY-SA 4.0 | © Garry Paxton 2008-2017, Steve Lee 2018-. <https://mulberrysymbols.org>. Upstream marks the set unmaintained. |
| Stellar Symbols | CC BY-SA 4.0 | © Colin McNamee |
| OpenMoji | CC BY-SA 4.0 | © OpenMoji Project. <https://openmoji.org> |
| Tawasol Symbols | CC BY-SA 4.0 | © Mada, Qatar. Arabic focused. <http://tawasolsymbols.org> |

Each entry records which set drew it. That field is not decoration: it is what
decides whether a shipped picture may be drawn when somebody switches that set
off in Picture sets.

A pack with no assets is not a pack. Bundling one of these sets means shipping
its images and declaring the asset directory in `pubspec.yaml`.

### Fetched on demand, commercial use permitted

`GlobalSymbolsPack` reaches six CC BY-SA sets through the Global Symbols API
(<https://globalsymbols.com>) so a caregiver adding a word does not have to
wait for a release to get a picture for it. Images are cached in application
documents, in a directory per set — the API answers with a catalogue number and
nothing else, so the path is the only record of which set drew a file that
survives the app being closed, and without it a set switched off would go on
drawing every picture chosen before somebody switched it off.

### The device's own emoji, **codepoints only, never glyphs**

The `system-emoji` pack offers the emoji the operating system can already
draw. It bundles **no pictures**. What it stores is the codepoint sequence,
which the app draws as text in whatever font the platform provides, the same
thing every text field on the device does, and a redistribution of nothing.
No emoji artwork set is bundled or redistributed by this project.

> ⛔ **Apple Color Emoji and Segoe UI Emoji are proprietary fonts.** Their
> glyph images may never be extracted, rasterized to files, bundled, or
> shipped. Any change that renders one of these characters into an image
> buffer and keeps the result has crossed that line, whatever it was for.

The bundled part is the search index, because the OS exposes no searchable
list of what it can draw:

| Data | License | Notes |
|---|---|---|
| Unicode CLDR emoji annotations | Unicode-3.0 | Emoji names and search words. © Unicode, Inc. <https://www.unicode.org/license.txt> |
| Unicode `emoji-test.txt` | Unicode-3.0 | Which sequences are emoji. Same terms. |

Generated by `tools/fetch_emoji_index.dart` into
`app/assets/symbols/system-emoji/manifest.json`, which carries the notice the
license requires and is read by the symbol credits screen inside the app.

A board using these renders differently on a different device, or after an OS
update. That is inherent and is not a bug.

### Optional downloads, **noncommercial only**

**These are never bundled.** They are fetched at runtime only if a user
chooses them, so the restriction attaches to that choice rather than to this
project's distribution.

| Set | License | Served by |
|---|---|---|
| ARASAAC | CC BY-NC-SA 4.0 | `ArasaacPack` |
| AAC Image Library | CC BY-NC-SA 4.0 | `globalsymbols-nc` — © AAC Image Library, <https://aacil.neocities.org> |

`globalsymbols-nc` is `GlobalSymbolsPack.nonCommercial()`: the same class and
the same API as the commercial pack, reaching a separate `nonCommercialSets`
list. Two lists rather than one list with a licence field, because a list where
the licence is a field is a list somebody filters wrong once — but every entry
carries `allowsCommercialUse: false` as well, and *that* is what the registry
reads. `SymbolRegistry.isSetEnabled` falls back to it for any set nobody has
answered about, so both of these arrive **off** in a release without anyone
migrating a stored settings map. A set added in a later release gets the same
treatment: correct from its licence, never inherited from what was stored
before it existed.

A fork that is sold drops these by removing the `nonCommercial` constructor and
`nonCommercialSets`, and the `ArasaacPack` file. Nothing outside `main.dart`
names either, and neither set record lives in `symbol_sets.dart` — the
noncommercial ones stay with the pack that reaches them precisely so this is a
deletion rather than an edit to a shared list that has to be got right.

ARASAAC attribution, required wherever its symbols appear:

> Author of the pictographic symbols: **Sergio Palao**. Origin: **ARASAAC**
> (<https://arasaac.org>). License: **CC (BY-NC-SA)**. Owner: **Government of
> Aragón (Spain)**.

> ⚠️ **If you are forking wordbridge to sell it**, or bundling it on hardware
> you sell, or putting it behind a paid support tier: ARASAAC cannot come with
> you. The `SymbolPack` boundary exists precisely so you can drop
> them and ship the CC BY-SA packs instead. A CI check fails the build if
> application code imports a specific pack directly, so this boundary stays
> real rather than aspirational.

### What an exported board carries

Exporting writes an `.obf` or `.obz` that leaves the device, so it is a
redistribution and is treated as one.

A picture's bytes are written into the file only when the license recorded on
that symbol is one this project has read and knows permits it — see
`redistributableSymbolLicenses` in `features/interop/obf_export.dart`, which is
an allowlist and not a test for "NC". Every embedded picture carries its
`license{}` and its author, which is what CC BY-SA requires of the file once it
is somewhere else.

Everything else is referenced rather than copied: the set and filename, the
credit, and a URL where there is one. That covers ARASAAC, whose images this
app never passes on, and it covers the system emoji, whose glyphs belong to the
operating system's font and may not be written into a file at all. The person
exporting is told, in the export screen, how many pictures were named rather
than carried and under which license.

### What may be added

A symbol set may be added only when its license permits redistribution, and it
may be bundled only when that license also permits commercial use. A set
licensed for use only inside the software of whoever publishes it is never
bundled, imported, or reproduced here.

---

## The optional neural voice

**Never bundled.** Kokoro-82M v0.19 is fetched at runtime, from
`k2-fsa/sherpa-onnx`'s release assets, only if a caregiver chooses it. Nothing
is sent anywhere afterwards: synthesis is local, and the download is the one
network call the feature makes.

| Part | License |
|---|---|
| Kokoro-82M weights | Apache-2.0 |
| `sherpa-onnx` runtime | Apache-2.0 |
| espeak-ng data (phonemizer) | GPL-3.0-or-later, used as a separate data file |

### What could not be verified

Kokoro's model card states its training data includes **"synthetic audio
generated by closed TTS models from large providers"**. Those providers
generally forbid training on their output in their terms of service.

**So the weights are offered under Apache-2.0 by people who may not have been
in a position to offer them.** This project cannot resolve that: the training
set is not published, and the license upstream asserts is the only claim there
is to go on.

It is written down here for the same reason the symbol licenses are. wordbridge
enforces a symbol license boundary in CI and publishes what it could not check;
a voice does not get a lower standard than a picture. If you are forking
wordbridge to sell it, this is the item to take advice on. It is a runtime
download rather than something this project distributes, which is why the
feature is built the way it is, but that is a shape of the problem rather than
an answer to it.

**The alternative, if that answer is not good enough for you:** StyleTTS 2,
which Kokoro is derived from, publishes LJSpeech and LibriTTS checkpoints,
LibriTTS being LibriVox public domain. `PublishedModel` in
`features/speech/neural/voice_model.dart` names the release as one value so
that swapping it is a value change rather than an edit in four places.
