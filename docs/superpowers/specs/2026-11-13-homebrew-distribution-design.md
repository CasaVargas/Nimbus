# Homebrew distribution

Date: 2026-11-13

## Why

Reach more people without losing the download count. A lot of Mac users install
everything with Homebrew and never visit a Releases page.

## Goals

- `brew install --cask nimbus` installs the same signed, notarized DMG as the Releases page.
- Brew installs are counted with every other download, with no new service.
- A published release reaches the tap without anyone editing a cask by hand.

Non-goals: a separate brew-only count, a second build or artifact, telemetry of any kind.

## Approaches

1. **Our own tap, `CasaVargas/tap` (chosen).** The tap already exists and ships Beltr,
   with a `brew style` + `brew audit` check on every PR. A cask there can go live today.
   Cost: users type a tap and (Homebrew 7) a `brew trust` step.
2. **Official `homebrew/cask`.** One short command and Homebrew's own install analytics
   on formulae.brew.sh. Not open to us yet: self-submitted casks are refused below the
   notability bar (roughly 75 stars, or 30 forks or watchers; Nimbus has 23 stars).
   Revisit when it clears; the tap cask is the starting point for that submission.
3. **A redirect or proxy in front of the DMG to split brew from direct downloads.**
   Rejected: a hosted service to run, and it would sit between users and a signed
   download for a number we do not need.

## Design

- **Cask** `Casks/nimbus.rb` in `CasaVargas/homebrew-tap`. Its `url` is the GitHub
  release asset `Nimbus-<version>.dmg`. `auto_updates true` (Sparkle updates in place),
  `depends_on macos: :sequoia`, no arch restriction (the DMG is universal). `uninstall`
  quits the app and unloads the backups launch agent. `zap` removes Nimbus's own data
  and leaves `~/.config/rclone` alone, because the rclone command line shares it.
- **Counting.** GitHub counts every fetch of a release asset, whoever asks. Because the
  cask downloads the release DMG itself, a brew install adds one to the same
  `download_count` that `scripts/download-badge.sh` and the site already sum. Nothing in
  the counter changes. The count stays a total: brew and direct are not told apart.
- **Bumps.** `.github/workflows/bump-homebrew.yml` runs when a release is published
  (drafts are published by a person, so the event fires) or on demand for a tag. It
  reads the checksum from the release's `.sha256` asset rather than downloading the DMG,
  so the bump itself does not add a download. It opens a PR on the tap, waits for the
  tap's audit and squash-merges it; a failed audit leaves the PR open and the run red.
  It needs the `HOMEBREW_TAP_TOKEN` secret (a PAT with Contents and Pull requests
  read/write on the tap), the same one Beltr's bump uses.
- **Known noise.** The tap's audit downloads the DMG once per bump PR, so each release
  starts with a count of about one that is not a person.
- **Docs.** README Install and the site's Get Nimbus section show the brew command next
  to the DMG.
