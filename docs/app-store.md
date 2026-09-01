# Shipping wordbridge to the App Store

The mechanical parts of a first iOS release, and the decisions behind them.
See REQUIREMENTS.md §4.52.

## The account

| | |
|---|---|
| Team | `98GHT62M9Q`, `Shehab Alnasrawi` |
| Kind | Individual, paid membership, **active** |
| Bundle id | `org.wordbridge.wordbridge` |
| Signing | Automatic. Development profiles run a year, not seven days |

An individual account puts the holder's legal name on the listing as the
seller. That is a real cost against §11's adoption problem — an AT coordinator
filling in a funding rubric cannot write a person's name where the form says
"local supplier" — and converting to an Organization account needs a legal
entity and a D-U-N-S number. Shipping under the individual account is the
decision for now, and converting later changes the listing name.

## Positioning

**Education, rated 4+, not the Kids Category.**

Education is where Proloquo2Go and LAMP Words for Life both sit. Medical invites
review questions about regulatory status and clinical claims that the evidence
section says wordbridge should not be inviting yet. The Kids Category bans
third-party analytics outright and requires a parental gate in front of every
external link; no mainstream AAC app is in it, and being there would be a claim
about who configures the app that is not true. A caregiver configures it. A
child uses it.

**Keep PRC's marks out of the metadata.** *LAMP* and *LAMP Words for Life* are
Prentke Romich Company trademarks. They may not appear in the app name, the
subtitle, the keywords, the bundle id or the screenshots. The comparison is
fair and belongs in prose on a website, not in a store listing where it reads
as an association.

## What is already done

- [x] `PrivacyInfo.xcprivacy`, declaring file timestamp access (`C617.1`), the
      report data types, and no tracking. **Required since May 2024; missing it
      is a rejection, not a warning.**
- [x] `NSPhotoLibraryUsageDescription` and `NSCameraUsageDescription`. Without
      these the symbol picker's "use my own photo" did not fail politely, it
      terminated the app on a real device.
- [x] `ITSAppUsesNonExemptEncryption` = `false`, so export compliance is not
      asked again on every upload. wordbridge encrypts nothing of its own:
      HTTPS for the intake and the optional downloads, a hash for the PIN.
- [x] `UIRequiresFullScreen`, orientation lock, and the Files keys.
- [x] An app icon at every size, including 1024.

## What is left

- [ ] **Decide the version.** `pubspec.yaml` is at `0.1.0+1`. TestFlight is
      happy with that; an App Store release conventionally is not. Phase 8 of
      the plan — scanning, switch access, dwell — is not built, so `1.0.0`
      would be claiming something. TestFlight at `0.1.x` first.
      `report.dart` carries `appVersion` and `appBuild` and a test pins them
      to `pubspec.yaml`, so both move together.
- [ ] **A privacy policy URL.** Required for every listing, and this one is
      unusually easy to write honestly: the app collects nothing unless
      somebody opens Reports and presses send. `docs/reporting.md` is most of
      the text already.
- [ ] **A support URL.** §11 is blunt about this: a GitHub Issues link scores
      zero on every row of the Training and Support tier an SLP fills in for
      funding. It is still what there is.
- [ ] **Screenshots**, at every required iPad size. The board, the editor
      showing a remap warning with real tap counts, the finder, and the voice
      screen.
- [ ] **Description and keywords.** Lead with what it does. No hype, and no
      evidence claim the Evidence section would not stand behind.
- [ ] **Age rating questionnaire.** Note the adult vocabulary band: profanity
      is available to teen and adult presets and is off by default below adult.
      Answer the questionnaire for what the app can display, not for the
      default.
- [ ] **Set the intake at build time** if reports are wanted in that build:
      `--dart-define=WORDBRIDGE_INTAKE_URL=… --dart-define=WORDBRIDGE_INTAKE_TOKEN=…`.
      Without them the Reports screen says so and sends nothing.
- [ ] **An archive build and an upload.** `flutter build ipa`, then Transporter
      or `xcrun altool`. The deploy script builds for a device, not for the
      store.

## Two things not to get wrong

**Never change the app icon without opt-in.** A parent in the research: *"My
son has been using lamp for eight years and now the poor kid can't find it with
visual recognition."* A company whose thesis is "never move anything" changed
the one glyph that gets a user into the app. Whatever the icon is at first
release is what it stays.

**An update must never reset a board.** Board layout is user data. The schema
is at 7 and migrations are additive only; `*.g.dart` is generated at build
time, which is why `deploy-ipad.sh` runs `build_runner` — a schema change once
shipped a binary whose Dart could not see its own column.
