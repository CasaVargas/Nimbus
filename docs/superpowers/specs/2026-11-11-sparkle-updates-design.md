# Updates through Sparkle (#100)

Date: 2026-11-11
Status: draft (option 1 of the triage on #100; awaiting Jon's review in the PR)

## Problem

Every new version is installed by hand: download the DMG, drag the app over
the old one. A user asked for Sparkle so Nimbus can update itself.

## Decision

Adopt Sparkle 2 as the updater. Update checks are **opt-in**.

Rejected: a home-made updater on the GitHub Releases API (replacing a running
app safely is security-sensitive work that Sparkle already does); a notice that
only links to the release (does not install anything, which is the request).

Accepted consequences:

- **First remote Swift package.** The north-star rule was "zero third-party UI
  dependencies". Sparkle is the one exception: Apple provides no updater for
  apps outside the App Store. `scripts/lint-package-resolved.sh` changes from
  "no remote package" to "no remote package except Sparkle".
- **Nimbus can contact the network for itself a second time** (the first is
  the rclone download, #70). The README and SECURITY.md said "no update
  pinging" / "no update checks". The promise becomes: none unless you turn
  them on or choose Check for Updates.

## Behaviour

### Opt-in

- `SUEnableAutomaticChecks` is left unset, so Sparkle's own behaviour applies:
  automatic checks start off, and on the second launch Sparkle asks once
  whether to check automatically. Nothing is requested before the user answers
  yes or chooses Check for Updates.
- No system profile is sent (`SUEnableSystemProfiling` stays off). A check is
  one HTTPS GET of the appcast; the user agent carries the app name and version.
- Settings > General > Updates has one switch, "Check for updates
  automatically", bound to `SPUUpdater.automaticallyChecksForUpdates`, and a
  "Check Now" button. The switch follows the answer given in Sparkle's prompt.
- The app menu has "Check for Updates…" under About.
- When a check finds a version, Sparkle's standard window shows the release
  notes and installs on the user's click. Its "install automatically in future"
  checkbox is left available.

### When the updater runs

The updater starts the first time the app becomes active. A login-item launch
and a backups-agent launch are hidden; Sparkle's permission prompt or an update
window must not appear from an app the user has not opened. Once the user opens
Nimbus the updater starts and stays running for the session.

The updater does not exist in:

- a test host or preview host (`LaunchContext`), like every other system-facing
  service;
- Debug builds, unless launched with `-debugEnableUpdater YES`. A development
  build must not offer to replace itself with the release.

In those cases the menu item and the Settings controls are disabled.

Installing an update quits Nimbus through the normal path, so the quit
confirmation for a running backup and the shutdown handler (unmount, stop
rclone) both run.

### Feed

- `SUFeedURL`: `https://github.com/CasaVargas/Nimbus/releases/latest/download/appcast.xml`.
  GitHub resolves `latest` to the newest published, non-prerelease release, so
  **publishing the draft release is what ships the update**; a draft is invisible
  to the feed. No extra host.
- The appcast has one item, the release it is attached to. Its enclosure is
  that release's DMG:
  `https://github.com/CasaVargas/Nimbus/releases/download/v<version>/Nimbus-<version>.dmg`.
  Sparkle installs from a DMG, so the release keeps one artefact.
- Release notes are the body of `docs/releases/<version>.md`, embedded as
  `<description sparkle:format="markdown">` (Sparkle 2.9+).
- `sparkle:minimumSystemVersion` comes from the built app's
  `LSMinimumSystemVersion`.

### Signing

- Updates are signed with an EdDSA (ed25519) key. The public key is
  `SUPublicEDKey` in the app; the private key is the `SPARKLE_PRIVATE_KEY`
  secret, with Jon's Keychain holding the original (`generate_keys`).
- `SUVerifyUpdateBeforeExtraction` is on: the DMG's signature is checked before
  it is mounted.
- Sparkle also checks the new app's code signature. A changed Developer ID
  is accepted when the EdDSA signature verifies (that is Sparkle's key
  rotation rule), so the EdDSA key is the one that must not leak.
- Losing the private key means no update can be signed for installed copies;
  users would have to install by hand once, as today. Keep a backup of the key.

### Version numbers

Sparkle orders versions by `CFBundleVersion`. It was a constant `1`, so no
build would ever have been newer than another. `CURRENT_PROJECT_VERSION` now
equals `MARKETING_VERSION` (one number to bump, `1.0.2` style), for the app and
the extension. About shows "Version 1.0.2" without the repeated build.

Versions up to 1.0.1 have no updater. The first release with Sparkle is
installed by hand; later ones update themselves.

## Implementation

| Piece | Where |
|---|---|
| Package | `Nimbus/project.yml`: `Sparkle`, `exactVersion: 2.10.1`, on the `Nimbus` target only. The extension does not link it. |
| Keys | `Nimbus/Config/Nimbus-Info.plist` (`INFOPLIST_FILE`, merged into the generated Info.plist): `SUFeedURL`, `SUPublicEDKey`, `SUVerifyUpdateBeforeExtraction`. |
| Service | `Nimbus/Nimbus/Services/UpdaterService.swift`: `@Observable @MainActor`, owns an `UpdateDriver` (protocol; `SparkleUpdateDriver` wraps `SPUStandardUpdaterController`). Tests use a fake driver. |
| UI | `AppCommands` (menu item), `GeneralSettingsView` (Updates section). |
| Lint | `scripts/lint-package-resolved.sh`: pins must be exactly `sparkle` from `https://github.com/sparkle-project/Sparkle`. |
| Signing the app | `scripts/package-release.sh` signs Sparkle's nested code inside-out (Installer.xpc, Downloader.xpc keeping its entitlements, Autoupdate, Updater.app, the framework) before the app. CI builds unsigned, so nothing else gives them a Developer ID signature and the notary service would reject the app. |
| Appcast | `scripts/make-appcast.sh`: after the DMG is notarized and stapled, signs it with Sparkle's `sign_update` (from the package's artefact bundle) and writes `dist/appcast.xml`. Runs when `NIMBUS_SPARKLE_KEY` is set. |
| Check | `scripts/verify-appcast.swift`: verifies the appcast's signature over the DMG with CryptoKit against the `SUPublicEDKey` of the app inside the DMG. A key mismatch fails the release instead of shipping an update nobody can install. |
| Release workflow | passes the secret, requires `dist/appcast.xml`, runs the check, uploads the appcast to the draft release. |

## Tests

- `UpdaterServiceTests`: the switch writes through to the driver; a change made
  by the driver (Sparkle's prompt) shows in the service; no driver means
  unavailable and no crash; start happens once.
- `scripts/lint-package-resolved.sh` against three fixtures: no pins, Sparkle
  only, Sparkle plus another package.
- `scripts/make-appcast.sh` + `scripts/verify-appcast.swift` against a throwaway
  key and a locally built DMG: verification passes, and fails for a tampered DMG
  and for a different key.
- Settings snapshot updated for the new section.
- Not testable before a release: the end-to-end update from one published
  version to the next. Check it by hand on the release after the first one
  with Sparkle.

## Release steps this adds (once)

`bash scripts/setup-sparkle-key.sh` on Jon's Mac, after a build: creates or
reuses the key in the login Keychain, writes the public key to
`Nimbus/Config/Nimbus-Info.plist`, sets the `SPARKLE_PRIVATE_KEY` secret and
checks that the two are a pair. Then commit the plist and back up the key.

## Wording changes

- README and SECURITY.md: update checks are off until you turn them on.
- Not changed here, for Jon to decide: `site/index.html` ("0 update pings") and
  the Reddit drafts in `docs/marketing/` ("no update pings", "no third-party
  Swift packages").
