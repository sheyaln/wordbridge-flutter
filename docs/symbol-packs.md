# Symbol packs

Symbols reach the grid through `SymbolPack` (`app/lib/features/symbols/`).
Nothing outside that directory imports a concrete pack. The reason is
licensing, not tidiness: see [NOTICE.md](../NOTICE.md) and the last section
here.

## What exists

| Pack | License | How it ships | Commercial use |
|---|---|---|---|
| `core` | CC BY-SA 4.0 | bundled, 274 pictures | yes |
| Emoji from this device | Unicode-3.0 (the index only) | index bundled, pictures drawn by the OS | yes |
| More pictures (Global Symbols) | CC BY-SA 4.0 | fetched on demand | yes |
| ARASAAC | CC BY-NC-SA | optional download, off until switched on | **no** |

`core` is one set assembled from four sources through Global Symbols, and its
manifest carries the credit for each picture individually. The sources are not
packs of their own:

| Source of a `core` picture | License | Credit |
|---|---|---|
| Mulberry Symbols | CC BY-SA 4.0 | © Garry Paxton 2008-2017, Steve Lee 2018-. <https://mulberrysymbols.org> |
| Stellar Symbols | CC BY-SA 4.0 | © Colin McNamee |
| Tawasol Symbols | CC BY-SA 4.0 | © Mada, Qatar. <http://tawasolsymbols.org> |
| OpenMoji | CC BY-SA 4.0 | © OpenMoji Project. <https://openmoji.org> |

A symbol set may be added only when its license permits redistribution.
A set licensed for use only inside the software of whoever publishes it is
never bundled, imported, or reproduced here.

Attribution for every pack must stay reachable from inside the running app,
not just from this repository. `SymbolPack.attribution` carries the string, and
the Symbol credits screen reads it along with the per symbol credits in the
`core` manifest.

## Bundled, fetched, and optional

**Bundled** packs ship in the binary under `assets/symbols/<pack>/`. They are
enabled by default because their licenses permit commercial use, so shipping
them enabled costs a downstream fork nothing. `core` and the emoji index are
the only two, and both are declared under `flutter: assets:` in
`app/pubspec.yaml`. `BundledSymbolPack` degrades to an empty pack when its
manifest is absent, so the app renders label only buttons rather than failing.

**Fetched on demand** is the Global Symbols pack, which reaches the same four
CC BY-SA sets over the network so a caregiver adding a word does not have to
wait for a release to get a picture for it. It is enabled by default, because
commercial use is permitted and nothing about it is restricted; what it costs
is a network call, and it fails soft when there is none.

**Optional** packs are CC BY-NC. `SymbolRegistry` keeps them completely inert,
not searched, not resolved, not drawn, until a person turns them on. Opting out
again stops resolving images already on disk. The restriction then attaches to
the user's choice rather than to this project's distribution. `ArasaacPack` is
registered in `main.dart` and reachable from caregiver settings under Pictures,
off until somebody turns it on.

The default for a pack a person has never touched is its own
`allowsCommercialUse`, not a saved list. A pack added in a later release
therefore gets the correct default rather than inheriting a choice set that
predates it.

## The device's own emoji

`SystemEmojiPack` implements `GlyphSymbolPack`: `resolve` answers with the
characters to draw rather than with anywhere to read bytes from, and
`SymbolPicture` draws them as text in the platform's own font.

> **Store the codepoint, never the picture.** Apple Color Emoji and Segoe UI
> Emoji are proprietary. Their glyphs may not be extracted, rasterized to
> files, bundled or shipped, and no step of this feature may write an image
> derived from a system font. Drawing the character is displaying text and
> redistributes nothing; capturing what it drew does not.

What is bundled is the search index, because the OS exposes no searchable list
of what it can draw. `tools/fetch_emoji_index.dart` builds it from Unicode CLDR
annotations and `emoji-test.txt`, both under the Unicode license, and writes
`app/assets/symbols/system-emoji/manifest.json`: names and keywords, about
1,500 emoji, no images. The generator pins both the CLDR release and the emoji
version; the emoji version is deliberately conservative, because a codepoint
the device's font lacks draws as a missing glyph box.

**Not a source for automatic attachment.** `AutoSymbol` skips every
`GlyphSymbolPack` outright. Emoji keywords are broad, and a match nobody is
looking at is a picture the board chose for somebody who cannot contradict it.
The picker is where these belong.

The same trade applies to anything built on it: the drawing differs on another
device and after an OS update, so a board exported to OBF renders differently
elsewhere. Per device convenience, not a portable symbol set.

## Adding a bundled pack

1. Confirm the license permits commercial use. If it does not, it is an
   optional download, not a bundled pack. There is no third option.
2. Drop images into `app/assets/symbols/<pack-id>/`.
3. Write `app/assets/symbols/<pack-id>/manifest.json`. Either a flat map of
   keyword to filename, keywords lowercase:

   ```json
   {
     "water": "water.png",
     "more": "more.png"
   }
   ```

   or the nested form, which also records which source set each picture came
   from. A pack assembled from several sets owes a different attribution per
   picture, and the nested form is what keeps that:

   ```json
   {
     "symbols": {
       "water": { "file": "water.svg", "set": "mulberry" }
     }
   }
   ```

   Entries whose value is neither a string nor a map with a `file` string are
   ignored. A keyword naming a file the build did not ship resolves to null and
   the button falls back to its label.

4. Declare the directory under `flutter: assets:` in `app/pubspec.yaml`. A pack
   with no assets is not a pack: it answers every search with nothing while the
   credits screen implies the app carries a symbol library it does not.
5. Add a `BundledSymbolPack` entry to `bundledSymbolPacks()` in
   `bundled_pack.dart` with the license identifier and attribution string.
6. Add the pack to the tables in `NOTICE.md` and above.

No code generation, no index build. A manifest and its images are the whole
installation.

## Adding a downloadable pack

Implement `DownloadingSymbolPack`, set `allowsCommercialUse` to match the
license, and follow what `global_symbols_pack.dart` and `arasaac_pack.dart` do:

- Store under `getApplicationDocumentsDirectory()/symbols/<pack-id>/`. **Never
  the cache directory.** The OS evicts caches under storage pressure, and an
  AAC user whose symbols vanish mid conversation has lost their voice.
- Write to a `.part` file and rename. A truncated file looks cached and renders
  broken for good.
- Time out, collapse concurrent requests for the same symbol into one, and do
  not retry a failure within a session.
- Fail soft. Return empty results, never throw.
- Emit on `available` when a download lands, so a grid already on screen can
  pick it up.

Two different jobs with two different standards of proof. `search` returns
ranked candidates for a person to choose between, and loose matching is fine
there because a caregiver is looking at them. Anything the app attaches to a
button unattended needs an exact label match: the search is a substring match,
so "all" returns Ball and "she" returns Sheep, and a plausible wrong picture is
a lie the user cannot contradict. `GlobalSymbolsPack.bestMatch` is the strict
one.

## Global Symbols API

```
https://globalsymbols.com/api/v1/labels/search?query={q}&symbolset={slug}&language=eng&limit={n}
```

- Set slugs, in preference order: `mulberry`, `stellar-symbols`, `tawasol`,
  `openmoji`. Mulberry leads because it is a purpose built AAC set with a
  consistent drawn style; the rest fill its gaps in abstract core vocabulary.
- Records carry `text` and a nested `picto` with `id` and `image_url`.
- `image_url` decides the extension on disk, PNG or SVG.
- `tools/fetch_symbols.dart` uses the same source to build the bundled `core`
  pack, so the offline and online paths agree on what a word looks like.

## ARASAAC API

Verified against the live service, not taken from the docs.

```
https://api.arasaac.org/api/pictograms/{lang}/search/{query}
https://api.arasaac.org/api/pictograms/{lang}/bestsearch/{query}
https://static.arasaac.org/pictograms/{id}/{id}_{res}.png
```

- `{lang}` is a bare language code. `en-US` returns nothing; `ArasaacPack.apiLocale`
  reduces vocabulary locale tags before use.
- Records carry `_id` and `keywords[].keyword`.
- `{res}` is **300, 500 or 2500 only**. Every other value 404s. wordbridge uses 500.
- `bestsearch` is tried first and the broad `search` is the fallback.

Wherever an ARASAAC picture appears, this attribution must appear with it:

> Author of the pictographic symbols: **Sergio Palao**. Origin: **ARASAAC**
> (<https://arasaac.org>). License: **CC (BY-NC-SA)**. Owner: **Government of
> Aragón (Spain)**.

## Resolution at render time

`SymbolResolver` walks: bundled asset, then a file already on disk, then a
queued download, then the label. Three rules, none negotiable:

- It never throws and never renders a broken image.
- It never blocks or delays a button press. Resolution is asynchronous and off
  the input path; the button speaks whether or not a picture ever arrives.
- A missing symbol is an absent result the UI draws as label only text. It is
  not an error state and nothing is reported to the user.

## Custom uploads

Photographs imported by a caregiver are resized to 512px on the longest edge,
saved as PNG, and **stripped of EXIF**. That last part is not optional:
these are pictures of children, and EXIF carries the GPS fix of wherever the
photo was taken, usually the family home. Contents are hashed with SHA-256 to
collapse repeat imports, and files land in application documents under
`symbols/custom/`.

## If you are forking this to sell it

Drop ARASAAC. Delete `arasaac_pack.dart`, remove the pack from
whatever wires up the registry, and ship the CC BY-SA packs instead. Both are
CC BY-NC: bundling either in a product you sell, including on hardware you
sell or behind a paid support tier, breaches the license.

The `SymbolPack` boundary exists so this is a deletion rather than a refactor.
`tools/check_symbol_boundary.sh` fails the build if application code outside
`features/symbols/` imports a concrete pack, which is what keeps that true.
`main.dart` is the one exception, because something has to name the packs to
construct the registry.
