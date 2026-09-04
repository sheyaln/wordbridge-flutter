# Publishing the downloadable APK

The website offers a direct APK download beside the Play badge, for people Play
cannot reach: a country where the listing is not available, a device without
Play Services, a school tablet that cannot use the store, or someone who wants
the build before the Play rollout reaches them.

The link never changes:

    https://github.com/sheyaln/wordbridge-flutter/releases/latest/download/wordbridge-aac.apk

GitHub resolves `latest/download/<name>` to the newest release's asset of that
name, so publishing a release is the whole of updating the site.

## Cutting a release

    git tag v0.1.0
    git push origin v0.1.0

The `release` job runs only for tags matching `v*`, and only after `check` and
`android` have passed. It builds a signed release APK, attaches it as
`wordbridge-aac.apk`, and generates notes from the commits since the last tag.

## The secrets it needs

Repository → Settings → Secrets and variables → Actions.

| Secret | What it is |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `base64 -i app/android/upload-keystore.jks` |
| `ANDROID_STORE_PASSWORD` | `storePassword` from `key.properties` |
| `ANDROID_KEY_PASSWORD` | `keyPassword` from the same file |
| `ANDROID_KEY_ALIAS` | `keyAlias` from the same file |
| `WORDBRIDGE_INTAKE_URL` | optional; where a crash report goes |
| `WORDBRIDGE_INTAKE_TOKEN` | optional; the intake credential |

Without the first four the job **fails rather than falling back**. The Gradle
config signs with the debug key when `key.properties` is absent, and an APK
signed that way looks like a release, installs like one, and can never be
updated by a real one.

## ⚠️ This APK is not the Play APK, and cannot become it

Play App Signing means Google re-signs every build with a key it holds. This
one is signed with the **upload** key. Two different signatures, so Android
will not update one with the other: a device that sideloads this and later
installs from Play has to uninstall first.

On this app, uninstalling deletes somebody's board — their vocabulary, their
learned positions, and their usage history. That is a person losing the way
they talk, not an app losing its settings.

So the download exists for people who cannot use Play at all, and the page that
offers it says which one to pick and why. **Back up before switching either
way** — Settings → Backups, and keep a copy off the tablet.

The alternative, if sideload-then-Play ever needs to work: ship the download
signed with the app signing key rather than the upload key, which means
exporting it from Play, which Google permits only if you opted out of having
them generate it. We did not, so this is not available and the warning stands.
