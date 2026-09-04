# Privacy policy amendment: backups to the user's own account

Proposed wording for `wordbridge-site/privacy.html`, which is not in this
repository. Effective date on that page is currently **September 3, 2026** and
needs bumping to the day this ships.

## What changed in the app

A device can now keep copies of its backups in the account already signed in on
it. Nothing reaches a Wordbridge AAC server, and there is no Wordbridge AAC account for
it to reach. The relevant facts, all of them checkable in
`app/lib/features/backup/`:

| | |
|---|---|
| Where a copy goes, iPad/iPhone | **either** the app's own iCloud container (`Documents`, in the user's iCloud account) **or** a folder the caregiver picks through the system folder picker — their Google Drive, Dropbox, OneDrive, iCloud Drive, or the device itself. iCloud container is the default. |
| Where a copy goes, Android | a folder the caregiver picks once through the system document picker — their Google Drive, OneDrive, or the tablet's own storage |
| Who chooses | asked on the **first run only**, per device, with "keep a copy" preselected. The place is part of that question where the device offers a choice, and is changeable afterwards under Settings → Backups. |
| Devices set up before this shipped | not switched on by the update; the stored answer stays "never asked", which is off |
| What is in a copy | the whole local database, byte for byte: boards, buttons, symbols, pictures, profiles, settings **and usage history** |
| When | at launch, at most once every 20 hours; whenever an app update changes how the board is stored; whenever someone presses "Back up now" |
| How many | five, oldest deleted, matching the device |
| Changing the place | Settings → Backups → *Where the copies go*. Copies already in the old place are **not moved and not deleted**. The app says so before the change and keeps naming the old place on that screen until the copies are gone. |
| Turning it off | Settings → Backups → *Keep a copy in …* — stops new copies, leaves existing ones alone |
| Deleting them | Settings → Backups → *Remove every copy from …*, or from iCloud Drive / the chosen folder directly |

**No Google or Dropbox credential, on either platform.** The folder picker is the
operating system's. What the app gets back is one folder — a persisted URI
permission on Android, a security-scoped bookmark on iOS — and nothing else on
the device or in the account is readable through it. The Drive REST API with
OAuth was rejected on both platforms: it needs a client tied to the signing key
and Google's verification of a sensitive scope, which is infrastructure on the
developer's side of a feature whose whole claim is that there is no developer
side.

**Not per profile.** A backup is the whole database, so it holds every profile
on the tablet. A per-profile switch would let one person's yes carry another
person's usage history into an account they were never asked about.

**Opt-in, with the answer preselected.** The question is put on the setup
screen with "keep a copy" already selected and both answers spelled out. It is
not defaulted silently, because what a copy carries includes a record of a
disabled person's speech.

---

## Replacement wording

### Section 2 › Backups — replace the whole `<h3>Backups</h3>` block

```html
<h3>Backups</h3>
<p>Wordbridge AAC can create a backup of its local database within the app's device storage. A backup contains the locally stored app data, including usage history.</p>

<h4>Copies in your own iCloud or Google account</h4>
<p>Wordbridge AAC can also keep copies of those backups in the cloud account already signed in on your device. This is offered once, during setup, and can be turned on or off at any time in Settings &rarr; Backups. Devices set up before this feature existed are not switched on by an update.</p>
<p>These copies go to <em>your</em> account, not to us:</p>
<ul>
  <li>On iPad and iPhone, either to Wordbridge AAC's own folder in your iCloud Drive, using the iCloud account signed in on the device, or to a folder you choose once through your device's own folder picker &mdash; your Google Drive, Dropbox, OneDrive, or the device's own storage. You choose which under Settings &rarr; Backups; iCloud is the default.</li>
  <li>On Android, to a folder you choose once through your device's own document picker &mdash; your Google Drive, another cloud provider you have installed, or the device's own storage.</li>
</ul>
<p><strong>We never receive these copies and cannot read them.</strong> There is no Wordbridge AAC server involved and no Wordbridge AAC account. Wordbridge AAC holds no credentials for your iCloud, Google, Dropbox or Microsoft account. Where copies go to Wordbridge AAC's own iCloud folder, the operating system grants the app a private folder inside your own iCloud storage. Where you choose a folder instead, on either platform, your device grants the app permission to that one folder and nothing else &mdash; the app never signs in to the provider and never sees the rest of your files. The copies count against your own cloud storage and are governed by that provider's privacy policy for your account, not by ours.</p>
<p>If you change where the copies go, copies already in the old place are left there: Wordbridge AAC does not move them and does not delete them. It tells you that before the change and keeps saying where they are under Settings &rarr; Backups, so you can delete them yourself. See Section 8.</p>
<p>A copy is the same file as the backup on the device: the complete app database, including usage history. As described under &ldquo;Usage history&rdquo; above, usage history records locations and times rather than words, but someone with access to both the history and the board could reconstruct some communication patterns. Anyone who can sign in to your cloud account can open these copies. Choose the account accordingly, and see Section 8 for how to delete them.</p>
<p>Copies are made when the app opens (at most once a day), when an app update changes how the board is stored, and when you press &ldquo;Back up now&rdquo;. Wordbridge AAC keeps the five most recent copies in the account and deletes older ones.</p>
<p>Your device's operating-system backup service may also independently copy application data to a service such as iCloud or Google backup, depending on your device settings. Those backups are separate from the copies described above, are controlled by your device and its operating system, and are not made or managed by Wordbridge AAC.</p>
<p>If you deliberately copy a backup somewhere else, Wordbridge AAC has no access to that copy and cannot delete it.</p>
```

### Section 1 › Information Wordbridge AAC does not collect — add after the bullet list

Insert immediately before the paragraph beginning "These things may be
processed or stored locally":

```html
<p>This remains true when cloud backups are switched on. A backup copied to your own iCloud or Google account is not transmitted to us: it goes from your device to your account, and we have no access to it. See Section 2 &rarr; Backups.</p>
```

### Section 8 › Data stored only on your device — replace the closing paragraph

Replace:

> A copy of a backup that has been moved somewhere outside the app is not
> accessible to Wordbridge AAC and cannot be deleted by us.

with:

```html
<h4>Backup copies in your own cloud account</h4>
<p>You control these entirely, because they are in your account and not ours.</p>
<ul>
  <li>Stop making new ones: Settings &rarr; Backups &rarr; turn off &ldquo;Keep a copy in&hellip;&rdquo;. Existing copies are left alone.</li>
  <li>Delete all of them: Settings &rarr; Backups &rarr; &ldquo;Remove every copy from&hellip;&rdquo;. This deletes them from the account. The board and the backups on the device are untouched.</li>
  <li>You can also delete them directly, from iCloud Drive or from the folder you chose, without opening Wordbridge AAC.</li>
  <li>If you have changed where copies go, the older ones are still in the previous place. Wordbridge AAC names it under Settings &rarr; Backups. Delete them there, or point Wordbridge AAC back at that place and use &ldquo;Remove every copy from&hellip;&rdquo;.</li>
  <li>Uninstalling Wordbridge AAC removes the app's local data and local backups from the device. It does <em>not</em> remove copies already in your cloud account &mdash; delete those first if that is what you want.</li>
</ul>
<p>A copy of a backup that has been moved somewhere outside the app is not accessible to Wordbridge AAC and cannot be deleted by us.</p>
```

### Section 9 › Children's privacy — add a paragraph

Nothing in the section as written becomes false, but its advice to review the
privacy settings now has a specific one to point at. Append after the last
paragraph:

```html
<p>One setting in particular is worth reviewing together: cloud backups. When they are on, a copy of the app's data &mdash; which includes the person's boards and usage history &mdash; is kept in the caregiver's own iCloud or Google account. It is not sent to us and we cannot read it, but anyone who can sign in to that account can open it. It is chosen during setup and reversible at any time in Settings &rarr; Backups.</p>
```

### Section 10 › Security — replace the second paragraph

Replace:

> The design of Wordbridge AAC also minimizes the information that needs to leave
> the device in the first place. Communication content and most information
> associated with a user's board remain local rather than being transmitted to
> our servers.

with:

```html
<p>The design of Wordbridge AAC also minimizes the information that needs to leave the device in the first place. Communication content and most information associated with a user's board remain local rather than being transmitted to our servers. Where a copy does leave the device &mdash; a cloud backup, if you have turned one on &mdash; it goes to your own account rather than to us, and is protected by that account's own sign-in and encryption.</p>
```

### Section 13 › A note about our approach — optional addition

```html
<p>Cloud backup is the same principle applied to a different failure. Families lose months of board customization when a tablet is lost or replaced, and a communication board is somebody's voice. So Wordbridge AAC helps you keep a copy &mdash; in your account, under your control, where we cannot see it &mdash; rather than becoming another party holding your data.</p>
```

---

## Store questionnaire impact

Both filings were made on the basis that nothing leaves the device. That claim
is now conditional. **Neither store's definition of "collect" is met** — both
define it as the *developer* receiving data — but both filings still need
attention, and one of them needs it before the current review finishes.

### Sequencing (do this first)

The policy amendment must not go live before the build that has the feature.
A policy describing cloud backup, in front of a reviewer running a build
without it, is a mismatch that gets flagged. If the binary currently in review
does **not** contain this change: hold the site update until that build ships,
then publish the amendment and the new build together.

### Apple — App Store privacy labels

- **Data collection answers: no change.** Apple defines collection as
  transmitting data off device *and* the developer or its partners retaining
  it. A file in the app's own iCloud container belongs to the user's iCloud
  account; Apple is not our third-party partner for it, and we retain nothing.
  "Data Not Collected" stays accurate for board data, usage history and
  profiles.
- **App Review Notes: must be updated.** Where a build carries the iCloud
  Documents entitlement (`com.apple.developer.icloud-container-identifiers`,
  container `iCloud.com.sheyaln.aac`), a reviewer will see a new capability on
  an app whose listing says nothing leaves the device. State plainly: backups
  go to the user's own iCloud container, opt-in at setup, no server of ours.
- **The folder destination needs no entitlement.** It is
  `UIDocumentPickerViewController` in folder mode plus a security-scoped
  bookmark — the same user-initiated grant any document-based app uses, no
  capability on the profile and no new `Info.plist` key. A build shipped
  without the iCloud entitlement still has a working cloud backup through it,
  which is why the two destinations are independent.
- **Capability provisioning.** iCloud Documents requires a paid account and the
  capability on the provisioning profile. See `docs/deploy-ipad.md`. The folder
  destination requires neither.
- **If Apple pushes back**, the fallback answer is *Other Data → App
  Functionality → not linked to identity → not used for tracking*. Do not
  volunteer it; it overstates what happens.
- Section 5.1.1 / 5.1.2 are unaffected: no new personal data is requested, and
  the entitlement grants no access to the user's iCloud beyond our own folder.

### Google Play — Data Safety form

- **"Does your app collect or share any of the required user data types?":
  answer unchanged.** Play defines collection as data leaving the device *to
  the developer or a third party acting for the developer*. The Android path
  writes through the Storage Access Framework to a folder the user picked in
  their own picker; the developer receives nothing and holds no credential.
- **Confirm this against the current Data Safety guidance before submitting.**
  The form has no "user's own cloud account" category, and Play's wording on
  user-initiated transfers through system pickers has moved before. If the
  reviewer's reading is that any off-device transfer counts, the honest
  declaration is *Files and docs → collected, not shared → App functionality →
  optional*, and "Users can request that data be deleted" answered yes
  (Settings → Backups → Remove every copy). "Data is encrypted in transit" is
  the provider's answer, not ours: the app hands the file to a
  `DocumentsProvider` on the device and never opens a socket, so where the
  folder is a cloud one the transfer and its encryption belong to that app.
- **Families policy.** If the listing is in the Designed for Families programme
  or targets children, re-read the disclosure requirements: this is a feature
  that moves a child's data off the device, even though it moves it to the
  parent's own account, and the programme's bar for disclosure is lower than
  the Data Safety form's.
- **No new permissions in the manifest.** The document picker needs none, which
  is part of why it was chosen over the Drive REST API. The Data Safety form's
  permissions cross-check will show nothing new. The same is true of the iOS
  folder picker: no entitlement, no `Info.plist` key, no new permission
  string.

### What is *not* affected

- No analytics SDK, advertising ID, or third-party telemetry is added. Section
  6 of the policy stands as written.
- Crash reports, voice measurements and person-submitted reports are untouched;
  they remain the only things that reach us, and they still go out only on the
  terms in Section 3.
- No account, sign-in, or identifier is added to the app. The device id in the
  usage log is unchanged and still opaque.
