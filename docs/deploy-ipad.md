# Deploying to an iPad

## The short version

```sh
cd app
flutter build ios --release
xcrun devicectl device install app --device "$DEVICE" build/ios/iphoneos/Runner.app
xcrun devicectl device process launch --device "$DEVICE" com.sheyaln.aac
```

Find `$DEVICE`: the CoreDevice UUID, **not** the hardware serial Flutter shows  
with `xcrun devicectl list devices`.

## Two traps, both hit on the first deploy

### `flutter run` and `flutter install` hang at "Uninstalling old version…"

No output, no error, no timeout. Flutter's own iOS deployment path stalls
against iOS 18 devices. Apple's `devicectl` does the same job in about eight
seconds.

Cost: no hot reload. For iteration, prefer the macOS build (`flutter run -d
macos`), which reloads normally, and use the iPad to verify the things only
real hardware can tell you: audio under the ringer switch, touch target size
under an actual finger, switch-access hardware.

### A locked iPad refuses the launch, and it looks like a failed install

```
The request was denied by service delegate (SBMainWorkspace) for reason:
Locked ("Unable to launch com.sheyaln.aac because the device was
not, or could not be, unlocked").
```

The install already succeeded; only the launch was refused. Unlock the iPad
and run the launch again: there is nothing to rebuild:

```bash
xcrun devicectl device process launch \
  --device "$DEVICE" \
  com.sheyaln.aac
```

The launch stays the proof the build arrived, because `devicectl` has been
seen to drop the connection mid-install and still exit 0. So a refused launch
cannot simply be ignored: it has to be retried until it succeeds, or the
install is unverified.

### Debug builds will not launch from the home screen

> "Debug mode Flutter apps can only be launched from Flutter tooling, IDEs with
> Flutter plugins or from Xcode"

A debug build needs the Dart VM service attached, so tapping the icon fails.
Use `--release` for anything anyone is going to actually pick up and use.
`--profile` also launches standalone and keeps performance instrumentation.

## Signing

A **free** Apple ID is enough for personal-device deployment.

1. Xcode → Settings (`⌘,`) → Accounts → **+** → Apple ID
2. Open `app/ios/Runner.xcworkspace`
3. Blue **Runner** project icon → **Runner** target (under TARGETS, not PROJECT)
   → **Signing & Capabilities**
4. Tick **Automatically manage signing**, pick your team
5. If provisioning fails, the bundle identifier is probably taken: change
   `PRODUCT_BUNDLE_IDENTIFIER` to something certainly yours

First install only: on the iPad, **Settings → General → VPN & Device
Management** → your developer profile → **Trust**.

> ⚠️ **Free personal-team builds stop working after 7 days.** The app refuses
> to launch until it is redeployed. That is survivable while developing and
> not survivable for someone who relies on the device to speak: if this goes
> to a real user, get a paid account first.

## What to verify on hardware, not in a simulator

- **Audio with the ringer switch muted.** `flutter_tts` goes silent under the
  silent switch unless the audio session category is `playback`. This is set in
  `lib/features/speech/speech_engine.dart`, but a documented API is not a
  tested one, and a muted tablet means a user who cannot speak.
- **Audio at distance, with background noise.** A voice that cannot be heard
  across a room or from the back seat of a car is a voice its owner has to be
  asked to repeat. Test it at distance, not held to your ear.
- **Touch targets under a real finger**, not a mouse cursor.
- **Nothing shifts between boards.** Tap a category, then home, and watch the
  bottom row.

## Turning on iCloud backups

`ios/Runner/Runner.entitlements` and the `NSUbiquitousContainers` key in
`Info.plist` are both in the repository. Neither is wired into the target,
because `CODE_SIGN_ENTITLEMENTS` and a provisioning profile carrying the iCloud
capability are the kind of thing that breaks signing quietly, and this is not
worth discovering on a build already in review.

Two steps in Xcode, once:

1. **Runner** target → **Signing & Capabilities** → **+ Capability** →
   **iCloud** → tick **iCloud Documents**, and add the container
   `iCloud.com.sheyaln.aac`. Xcode writes `CODE_SIGN_ENTITLEMENTS` for you; if
   it creates a second entitlements file, point the setting back at
   `Runner/Runner.entitlements` so the container ids match this repository.
2. Rebuild. A paid account is required — the iCloud capability is not available
   to a free personal team.

Until then the app answers "this tablet is not signed in to iCloud" on the
backups screen and keeps taking local backups. That is the intended state for a
build without the capability, not a bug to chase.

**The other destination needs none of this.** Settings → Backups → *Where the
copies go* → **A folder you choose** is `UIDocumentPickerViewController` in
folder mode plus a security-scoped bookmark: no entitlement, no capability on
the profile, no `Info.plist` key. It reaches iCloud Drive, Google Drive,
Dropbox, OneDrive and anything else with a File Provider extension on the
device, and it works on a free personal team. On a build with no iCloud
capability it is the only destination that does anything.

### What to verify on hardware

- **A copy actually arrives.** Back up now, then Files → iCloud Drive →
  Wordbridge AAC. The file's name carries the date; the backups screen should
  say the same date under "Last copied to iCloud".
- **A restore onto a second device.** Sign a second iPad into the same account,
  install, set up, then restore from the copy. This is the whole feature: a
  board that comes back on hardware that has never held it.
- **A tablet signed out of iCloud.** The screen must say so and offer the
  device backups, not fail silently.
- **A file iCloud has evicted.** Restore something old enough to have been
  purged from local storage; `CloudBackup.swift` waits for the download, and
  the wait is the part a simulator cannot exercise.
- **The folder picker, against a real provider.** Install Google Drive or
  Dropbox, then Settings → Backups → *Where the copies go* → **A folder you
  choose**. Check the row afterwards names the provider rather than "a folder";
  `CloudFolder.name(of:)` reads that off the `Library/CloudStorage` path, which
  only exists on a device with the extension installed.
- **The bookmark across a relaunch and a reboot.** Force-quit, reopen, confirm
  a copy still goes up without the picker reappearing. A bookmark taken outside
  its security scope resolves fine on the first run and fails later, which is
  the failure worth catching before somebody depends on it.
- **A folder that goes away.** Uninstall the provider app, or revoke the
  folder. The screen must say the folder can no longer be reached, keep taking
  local backups, and offer *Choose a different folder* as the way back.
- **Changing the destination.** Switch from iCloud to a folder with copies
  already in iCloud. The warning must name them before the change, the iCloud
  copies must still be in Files afterwards, and the screen must keep saying
  where they are.
