# Symbol packs

Symbols reach the grid through `SymbolPack` (`app/lib/features/symbols/`).
Nothing outside that directory imports a concrete pack. The reason is
licensing, not tidiness — see [NOTICE.md](../NOTICE.md) and the last section
here.

## What exists

| Pack | Licence | Shipped | Commercial use |
|---|---|---|---|
| Mulberry Symbols | CC BY-SA (version unconfirmed) | bundled | yes |
| OpenMoji | CC BY-SA 4.0 | bundled | yes |
| Twemoji | CC BY 4.0 | bundled | yes |
| Tawasol Symbols | CC BY-SA (version unconfirmed) | bundled | yes |
| ARASAAC | CC BY-NC-SA | opt-in download | **no** |
| Sclera | CC BY-NC | not implemented | **no** |

PCS, SymbolStix, Widgit and Unity are proprietary. They are not bundled, not
downloadable, and not to be reproduced.

Attribution for every pack must stay reachable from inside the running app,
not just from this repository. `SymbolPack.attribution` carries the string.

## Bundled vs opt-in

**Bundled** packs ship in the binary under `assets/symbols/<pack>/`. They are
enabled by default because their licences permit commercial use, so shipping
them enabled costs a downstream fork nothing.

**Opt-in** packs are CC BY-NC. `SymbolRegistry` keeps them completely inert —
not searched, not resolved, not drawn — until a person turns them on. Opting
out again stops resolving images already on disk. The restriction then attaches
to the user's choice rather than to this project's distribution.

Assets are not in the repository yet. `BundledSymbolPack` degrades to an empty
pack when its manifest is absent, so the app renders label-only buttons rather
than failing.

## Adding a bundled pack

1. Confirm the licence permits commercial use. If it does not, it is an opt-in
   download, not a bundled pack. There is no third option.
2. Drop images into `app/assets/symbols/<pack-id>/`.
3. Write `app/assets/symbols/<pack-id>/manifest.json` — a flat map of keyword
   to filename, keywords lower-case:

   ```json
   {
     "water": "water.png",
     "more": "more.png"
   }
   ```

   Entries whose value is not a string are ignored. A keyword naming a file the
   build did not ship resolves to null and the button falls back to its label.

4. Declare the directory under `flutter: assets:` in `app/pubspec.yaml`.
5. Add a `BundledSymbolPack` entry to `bundledSymbolPacks()` in
   `bundled_pack.dart` with the licence identifier and attribution string.
6. Add the pack to the table in `NOTICE.md` and to the table above.

No code generation, no index build. A manifest and its images are the whole
installation.

## Adding a downloadable pack

Implement `DownloadingSymbolPack`, set `allowsCommercialUse` to false, and
follow what `arasaac_pack.dart` does:

- Store under `getApplicationDocumentsDirectory()/symbols/<pack-id>/`. **Never
  the cache directory.** The OS evicts caches under storage pressure, and an
  AAC user whose symbols vanish mid-conversation has lost their voice.
- Write to a `.part` file and rename. A truncated file looks cached and renders
  broken for good.
- Time out, single-flight concurrent requests for the same symbol, and do not
  retry a failure within a session.
- Fail soft. Return empty results, never throw.
- Emit on `available` when a download lands, so a grid already on screen can
  pick it up.

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

## Resolution at render time

`SymbolResolver` walks: bundled asset, then a file already on disk, then a
queued download, then the label. Three rules, none negotiable:

- It never throws and never renders a broken image.
- It never blocks or delays a button press. Resolution is asynchronous and off
  the input path; the button speaks whether or not a picture ever arrives.
- A missing symbol is an absent result the UI draws as label-only text. It is
  not an error state and nothing is reported to the user.

## Custom uploads

Photographs imported by a caregiver are resized to 512px on the longest edge,
re-encoded as PNG, and **stripped of EXIF**. That last part is not optional:
these are pictures of children, and EXIF carries the GPS fix of wherever the
photo was taken — usually the family home. Contents are hashed with SHA-256 to
de-duplicate repeat imports, and files land in application documents under
`symbols/custom/`.

## If you are forking this to sell it

Drop ARASAAC and Sclera. Delete `arasaac_pack.dart`, remove the pack from
whatever wires up the registry, and ship the CC BY-SA packs instead. Both are
CC BY-NC: bundling either in a product you sell — including on hardware you
sell, or behind a paid support tier — breaches the licence.

The `SymbolPack` boundary exists so this is a deletion rather than a refactor.
A CI check fails the build if application code imports a concrete pack
directly, which is what keeps that true.
