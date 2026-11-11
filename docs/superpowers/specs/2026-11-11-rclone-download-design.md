# Download rclone on first launch (#70)

Date: 2026-11-11
Status: approved (option (b), Jon, 2026-11-11)

## Problem

Nimbus needs an rclone binary and today expects the user to have run
`brew install rclone`. A user without Homebrew gets an error card ("Failed to
start rclone: …") and no way forward from inside the app.

## Decision

When no usable rclone is found, the onboarding flow offers to download the
official rclone build from rclone.org, verifies it, and installs it to a folder
Nimbus owns. Homebrew/`PATH` detection and the user-configurable path stay as
they are, and a user's own rclone always wins over the downloaded one.

Rejected: (a) keep Homebrew as a hard prerequisite (two-step install, needs
Homebrew); (c) bundle rclone in the app (ships a third-party binary we must
sign, notarise and keep current; contradicts "never bundles rclone").

Accepted consequence: Nimbus itself touches the network for this download, so
the privacy wording in the README and on the site changes (see below).

## Behaviour

### When the offer appears

"Usable" means `FileManager.isExecutableFile(atPath: settings.rcloneBinaryPath)`.
Path resolution order (`RcloneLocator`):

1. A path the user set in Settings > Advanced (persisted `rcloneBinaryPath`).
2. `/opt/homebrew/bin/rclone`, `/usr/local/bin/rclone`, `/usr/bin/rclone`.
3. The Nimbus-managed copy (below).
4. Fallback `/usr/local/bin/rclone` (not executable → offer appears).

The onboarding "Connection Engine" card shows the offer instead of the raw
launch error when the configured path is not executable. It never downloads
without the click.

### Download

- Version: `https://downloads.rclone.org/version.txt` (`rclone v1.76.0`),
  parsed to `1.76.0`.
- Architecture: `arm64` on Apple silicon, `amd64` on Intel. Decided from the
  hardware (`sysctl hw.optional.arm64`), not the build slice, so a Nimbus
  running under Rosetta still gets the native arm64 rclone.
- Archive: `https://downloads.rclone.org/v<ver>/rclone-v<ver>-osx-<arch>.zip`.
- Downloads go through `URLSession` over HTTPS only.

### Verification

- The archive's SHA-256 must match the line for its file name in **both**
  `https://downloads.rclone.org/v<ver>/SHA256SUMS` and
  `https://github.com/rclone/rclone/releases/download/v<ver>/SHA256SUMS`.
  Two independent hosts must agree, so a compromise of one host is not enough
  to ship a bad binary.
- `SHA256SUMS` is a PGP clear-signed file. v1 does **not** verify the PGP
  signature: macOS ships no `gpg`, and bundling an OpenPGP implementation for
  one check is out of proportion. The parser skips the armour lines and reads
  only `<64 hex>  <name>` lines. The two-host cross-check is the mitigation;
  signature verification is a possible follow-up.
- Any mismatch, a missing line, or a malformed hash fails the install and
  nothing is written to the install folder.

### Install

- Location: `~/Library/Application Support/Nimbus/rclone/rclone` (Nimbus is
  not sandboxed). One binary; a new install replaces it atomically
  (`FileManager.replaceItemAt`).
- Extraction: `/usr/bin/ditto -x -k` into a temporary folder, then take
  `rclone-v<ver>-osx-<arch>/rclone`.
- Permissions: `0755`.
- Quarantine/codesign: rclone's macOS builds are ad-hoc, linker-signed and not
  notarised. Files that `URLSession` writes are not quarantined (Nimbus does
  not set `LSFileQuarantineEnabled`), so Gatekeeper does not assess the binary
  and it runs. Nimbus still removes `com.apple.quarantine` defensively and does
  **not** re-sign the binary.
- Sanity check: run `rclone version` and require it to report the expected
  version before the install counts.
- After install Nimbus sets `rcloneBinaryPath` to the managed path and retries
  the daemon.

### Updates

v1: a manual **Check for rclone update** button in Settings > Advanced, shown
only when the active binary is the Nimbus-managed copy. It compares
`version.txt` with the installed version and reinstalls through the same
verified path. No background checks and no update pinging. A Homebrew rclone
is updated by Homebrew.

### Failure states

| Failure | Shown as |
|---------|----------|
| Offline / HTTP error / timeout | "Couldn't reach rclone.org. Check your connection and try again." + Try Again |
| Unparseable `version.txt` | "rclone.org returned an unexpected version." + Try Again |
| Checksum missing or mismatched (either host) | "The download didn't match rclone's published checksum, so it wasn't installed." + Try Again |
| Extraction / binary missing / write failure | "Couldn't install rclone: <reason>." + Try Again |
| `rclone version` fails after install | "The downloaded rclone didn't run." + Try Again |

Every failure leaves the previous binary (if any) untouched. The card always
keeps a secondary "Use Homebrew instead" hint (`brew install rclone`) and a
Retry that re-detects.

## Code

- `Services/RcloneInstaller.swift`
  - `RcloneRelease` (pure): version parsing, arch, URL building.
  - `RcloneChecksums` (pure): parse `SHA256SUMS`, look up a file, verify data.
  - `RcloneInstaller` (`@Observable @MainActor`): state machine
    `idle → checking → downloading → verifying → installing → installed | failed`,
    network via an injectable fetcher for tests.
- `State/AppSettings.swift`: managed path joins the probe list (after the
  system paths).
- `Views/Onboarding/OnboardingView.swift`: the Connection Engine card shows the
  offer and progress.
- `Views/Settings/AdvancedSettingsView.swift`: "Check for rclone update".

Tests (`NimbusTests/RcloneInstallerTests.swift`): version parsing, arch and URL
building, `SHA256SUMS` parsing (armour, CRLF, bad lines), lookup and
verification, cross-host disagreement, and the installer state machine with a
fake fetcher.

## Wording change

README, "It integrates with the system…" paragraph:

> There is no account, no sign-in, no telemetry and no update pinging. rclone
> does all the cloud traffic; Nimbus itself only goes online if you ask it to
> download rclone for you (from rclone.org, checked against rclone's published
> checksums).

README prerequisite: "rclone: Nimbus uses your Homebrew rclone
(`brew install rclone`) if you have one, or offers to download the official
build on first launch." The architecture table row changes from "Nimbus never
bundles or patches it" to "Nimbus never bundles or patches it; it can download
the official build for you."

The site (casavargas.app/nimbus, `casavargas.github.io` repo) needs the same
change; it is out of scope for this PR.
