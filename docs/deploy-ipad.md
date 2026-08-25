# Deploying to an iPad

## The short version

```sh
cd app
flutter build ios --release
xcrun devicectl device install app --device "$DEVICE" build/ios/iphoneos/Runner.app
xcrun devicectl device process launch --device "$DEVICE" org.wordbridge.wordbridge
```

Find `$DEVICE` — the CoreDevice UUID, **not** the hardware serial Flutter shows —
with `xcrun devicectl list devices`.

## Two traps, both hit on the first deploy

### `flutter run` and `flutter install` hang at "Uninstalling old version…"

No output, no error, no timeout. Flutter's own iOS deployment path stalls
against iOS 18 devices. Apple's `devicectl` does the same job in about eight
seconds.

Cost: no hot reload. For iteration, prefer the macOS build (`flutter run -d
macos`), which reloads normally, and use the iPad to verify the things only
real hardware can tell you — audio under the ringer switch, touch target size
under an actual finger, switch-access hardware.

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
5. If provisioning fails, the bundle identifier is probably taken — change
   `PRODUCT_BUNDLE_IDENTIFIER` to something certainly yours

First install only: on the iPad, **Settings → General → VPN & Device
Management** → your developer profile → **Trust**.

> ⚠️ **Free personal-team builds stop working after 7 days.** The app refuses
> to launch until it is redeployed. That is survivable while developing and
> not survivable for someone who relies on the device to speak — if this goes
> to a real user, get a paid account first.

## What to verify on hardware, not in a simulator

- **Audio with the ringer switch muted.** `flutter_tts` goes silent under the
  silent switch unless the audio session category is `playback`. This is set in
  `lib/features/speech/speech_engine.dart`, but a documented API is not a
  tested one, and a muted tablet means a user who cannot speak.
- **Audio at distance, with background noise.** Parents of LAMP users rated the
  app down for a decade over output being too quiet to hear from the back seat
  of a car.
- **Touch targets under a real finger**, not a mouse cursor.
- **Nothing shifts between boards.** Tap a category, then home, and watch the
  bottom row.
