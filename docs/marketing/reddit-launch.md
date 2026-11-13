# Reddit launch posts (1.0)

Drafts, ready to paste. Written 2026-11-11 against v1.0.1; brought up to v1.2.0 on 2026-11-12 (updates through Sparkle shipped in 1.1.0, so "no update pings" and "no third-party packages" came out).

Links used everywhere:

- Repo: https://github.com/CasaVargas/Nimbus
- Download: https://github.com/CasaVargas/Nimbus/releases/latest
- Page: https://casavargas.app/nimbus/

## Order and timing

One account posting the same app to many subreddits inside an hour gets caught by Reddit's spam filter, and a removed post still uses up r/macapps' one-per-30-days slot. So: different text per subreddit, spread over about three days, and stay in each thread answering comments for the first two hours (that is what ranks a post).

| When | Where | Why |
|---|---|---|
| Day 1, 8-10am ET | r/rclone | The exact audience; small but every reader is a potential user |
| Day 1, same morning | forum.rclone.org, "Related" category | Not Reddit, but it is where rclone users actually are |
| Day 1 or 2, 8-10am ET weekday | Show HN | The largest single source of traffic available for a free open-source Mac app |
| Day 2 | r/macapps | Largest Mac-app audience on Reddit; strict rules, see below |
| Day 2 | r/opensource | GPL angle |
| Day 3 | r/DataHoarder | Backups angle |
| Day 3 | r/swift or r/SwiftUI | Engineering angle, no download pitch |
| Any Friday | r/selfhosted New Project Megathread | Main-feed posts for new projects get removed there |

Check each sidebar before posting: the rules below came from mirrors dated March to July 2026.

## Before the first post

- Install the latest DMG (`Nimbus-1.2.0.dmg`) from the release page on a Mac and add a cloud. 0.9.0 passed notarization and did not launch, and 1.1.0 opened a stack of Add Cloud windows, so check the build people will actually download.
- Have 3 images ready: `docs/screenshots/window-home.png`, `window-finder.png`, `window-backups.png`.

---

## r/rclone

**Title:** I made a native Mac app on top of rclone: Finder integration, scheduled backups, your existing rclone.conf. Free, GPL

**Body:**

I've used rclone for years and wanted a Mac front end that didn't feel like a web page, so I wrote one. It's called Nimbus.

It doesn't reimplement anything. It starts your own rclone binary as `rclone rcd` on loopback and talks to the RC API, so:

- Every backend rclone has works, and Add Remote is driven by rclone's own config questions, so new backends need no app update
- It reads and writes your normal `rclone.conf`. The CLI keeps working beside it
- It uses your Homebrew rclone if you have one. It never bundles or patches rclone

What the app adds:

- Remotes in Finder's sidebar through a File Provider extension (files download on demand, you can pin folders to keep them local), or as NFS volumes via `rclone serve nfs` if you want a classic mount. No macFUSE
- Scheduled backups with a preview before the first run (a dry run you can read), exclude lists, a versions folder and a removal limit
- A browser with Quick Look, drag and drop across remotes, and file-name search across every remote at once
- A guided crypt setup, a folder compare, and version history for S3 and B2
- Optional: encrypt rclone.conf with rclone's own config encryption, password kept in the Keychain and passed with `--password-command`

No account, no telemetry, and it looks for updates only if you turn that on. Swift and SwiftUI, no Electron. macOS 15 or later, Apple Silicon and Intel. Share links need rclone 1.76 or later.

It's free, including the signed and notarized build, and GPL-3.0.

Repo: https://github.com/CasaVargas/Nimbus
Download: https://github.com/CasaVargas/Nimbus/releases/latest

I'm the author. It's a 1.0 from one person, so there will be bugs; I'd like to hear which backends misbehave.

---

## r/macapps

First attempt (2026-11-12) was auto-removed twice over: the labels were bold headings without a colon and there was no Trust label, and the "Read The Rules" acknowledgement had not been submitted. A formatting removal can be reposted within 48 hours without losing the 30-day slot.

Before reposting:

1. Subreddit menu > "Read The Rules" > submit the acknowledgement.
2. Account needs 200+ Reddit karma and 60+ days of age (Rule 6).
3. Flair: **Free**. Title starts with `[OS]`.
4. Each label starts its own line, spelled exactly `Problem:`, `Comparison:`, `Pricing:`, `Trust:`.
5. Trust path is GitHub. Under 100 stars that path needs a LinkedIn link, which is in the Trust line below.

**Title:** [OS] Nimbus: a free native Mac app that puts 50+ cloud services (Google Drive, OneDrive, S3, B2) in Finder

**Body:**

I'm the developer.

Problem: I keep files in several clouds and wanted one native Mac app that shows them all in Finder and backs them up on a schedule, instead of a separate vendor app for each.

What it does: your clouds appear in Finder's sidebar, files download when you open them, and you can pin folders to keep them on the Mac. The app has a file browser with Quick Look and drag and drop between clouds, scheduled backups with a preview before the first run, search across every cloud at once, and a Home screen showing free space on each. It is SwiftUI and AppKit, no Electron, and uses rclone underneath, which is how it supports 50+ services. No account, no telemetry. macOS 15 or later, Apple Silicon and Intel.

Comparison:

- Mountain Duck. Nimbus is better on price (free against a paid license), it is open source, it covers 50+ services against 19 protocols, and it has scheduled backups. Mountain Duck is better on maturity (many years of releases), it also runs on Windows, and it opens Cryptomator vaults.
- ExpanDrive. Nimbus is better in being open source, covering 50+ services against 15, and having scheduled backups with a preview. ExpanDrive is better in running on Windows and Linux as well, and in having a much longer track record.

Nimbus is a new 1.x and has no Spotlight search for cloud files and no Share Sheet yet.

Pricing: $0. Free with no paid tier, no in-app purchase and no subscription, for the source and the signed build alike. GPL-3.0. Download: https://github.com/CasaVargas/Nimbus/releases/latest

Trust: GitHub. Source: https://github.com/CasaVargas/Nimbus. LinkedIn: https://www.linkedin.com/in/jvargas1023/. The build is Developer ID signed and notarized; privacy: https://casavargas.app/nimbus/#privacy

---

## r/opensource

**Title:** Nimbus: a GPL-3.0 native macOS cloud storage manager built on rclone

**Body:**

I've released Nimbus, a Mac app for browsing, mounting and backing up cloud storage. I'm the author.

It is a front end for rclone: it runs your rclone binary as a local daemon and talks to its RC API, so it supports everything rclone does (S3, Google Drive, OneDrive, Dropbox, B2, SFTP, WebDAV and so on) and shares rclone's config file with the command line.

- GPL-3.0-or-later, and the signed, notarized build is free as well. No paid tier, no account, no telemetry
- Swift 6 and SwiftUI, with one third-party Swift package: Sparkle, for updates (a lint step fails the build if another is added)
- Finder integration through Apple's File Provider, or NFS mounts
- Scheduled backups with a preview, search across clouds, encrypted folders, folder compare

The closest alternatives on the Mac are Mountain Duck and ExpanDrive, both closed source, and Cyberduck, which is open source but doesn't mount.

Design specs are in the repo under `docs/superpowers/specs/`. Issues and pull requests are welcome.

https://github.com/CasaVargas/Nimbus

---

## r/DataHoarder

**Title:** Free Mac app for scheduled rclone backups to any cloud, with a preview before anything is copied or removed

**Body:**

I wrote a Mac app called Nimbus that sits on top of rclone. I'm posting the part this subreddit would care about: backups.

- Back up a folder or a whole cloud to another cloud or folder, on a schedule
- A preview before the first run that lists what will be copied and what will be removed
- A removal limit: if a run would remove more than you allow, it stops
- Replaced and removed files go to a versions folder instead of disappearing
- Transfers say whether rclone verified them by checksum or only by size
- Version history and restore for S3 and Backblaze B2
- Backups can keep running while the app is closed (opt-in)

It uses your own rclone and your existing `rclone.conf`, so nothing is locked into the app, and anything it does you can also do from the command line.

Free and GPL-3.0. No account, no telemetry. macOS 15 or later.

https://github.com/CasaVargas/Nimbus

---

## r/swift (or r/SwiftUI)

**Title:** I shipped a Finder-style file manager in SwiftUI with a File Provider extension and one dependency. Notes on what was hard

**Body:**

Nimbus is an open-source macOS cloud storage app (GPL-3.0, Swift 6 strict concurrency). The code is public, so here is what I'd tell someone starting the same thing.

- **The file table is AppKit.** SwiftUI's `Table` could not match Finder's selection, type-to-select and drag behavior. Everything around it is SwiftUI
- **Developer ID builds lose a `group.` app group.** Without a provisioning profile macOS ignores that entitlement, so the File Provider extension could not read what the app wrote. It worked in every debug build and failed only in the notarized release. A team-ID-prefixed group fixed it
- **A notarized, Gatekeeper-accepted build can still fail to launch.** A re-sign left a development profile and restricted entitlements in place. The packaging script now launches the app before it builds the DMG
- **`NSFileProviderReplicatedExtension` change tracking** is done by diffing persisted directory snapshots, because the backend (rclone) has no change feed for most providers
- **One third-party package.** Sparkle, for updates. The rclone client is a local package over `URLSession`; a pre-build lint fails if any other dependency is added

Source: https://github.com/CasaVargas/Nimbus

Happy to answer questions about any of it.

---

## r/selfhosted (New Project Megathread comment)

Nimbus: a free, GPL-3.0 native Mac app on top of rclone. If your storage is your own (MinIO or any S3-compatible, SFTP, WebDAV, Nextcloud), it shows up in Finder's sidebar, and you can schedule backups from the Mac to it or between remotes, with a preview first. No account, no telemetry, uses your own rclone and rclone.conf. I'm the author. https://github.com/CasaVargas/Nimbus

If the megathread asks about AI involvement, answer it plainly.

---

## Show HN

**Title:** Show HN: Nimbus – A native macOS cloud storage manager built on rclone (GPL)

**URL:** https://github.com/CasaVargas/Nimbus

**First comment:**

I'm the author. Nimbus is a Mac app for browsing, mounting and backing up cloud storage. It runs your rclone binary as a daemon on loopback and talks to its RC API, so it supports whatever rclone supports and shares its config file with the command line.

It is Swift and SwiftUI, with AppKit for the file table, and one third-party package (Sparkle, for updates). Remotes show up in Finder through a File Provider extension, or as NFS mounts. There are scheduled backups with a preview, search across remotes, and a guided crypt setup.

It is free, including the signed build, and has no account or telemetry. My two paid apps fund it.

Known gaps: no Spotlight indexing of cloud files, no Share Sheet, and macOS 15 or later only.

---

# General-audience posts

Plain language, no rclone internals. Same spacing rule: two or three a day at most, different text each.

## r/coolgithubprojects

Link post to the repo. Pick the Swift flair if the form asks for one.

**Title:** Nimbus: every cloud drive you have (Google Drive, OneDrive, Dropbox, S3, 50+ more) in Finder, from one free native Mac app

**URL:** https://github.com/CasaVargas/Nimbus

---

## r/SideProject

**Title:** I built a free Mac app that puts all your cloud drives in Finder. Just shipped 1.0

**Body:**

I have files spread over Google Drive, S3 and Backblaze, and I got tired of running a different app for each one. So I built Nimbus.

What it does:

- Your clouds show up in Finder's sidebar like any other drive. Files download when you open them
- One window to browse all of them, with drag and drop from one cloud to another
- Backups on a schedule, and it shows you what it is going to do before it does it
- Search for a file name across every cloud at once

It works with Google Drive, OneDrive, Dropbox, S3, Backblaze and about 50 others, because it is built on an open-source tool called rclone.

It's free, with no account and no tracking, and the code is open. I make my living from two other apps, so this one doesn't need to earn anything.

It's a proper Mac app, not a web page in a window. Needs macOS 15 or later.

Download: https://github.com/CasaVargas/Nimbus/releases/latest
Code: https://github.com/CasaVargas/Nimbus

Tell me what breaks.

---

## r/MacOS

Check the sidebar first: self-promotion may be limited to certain days or threads.

**Title:** I made a free app that puts Google Drive, OneDrive, Dropbox and others in Finder without installing each company's app

**Body:**

I'm the developer. Nimbus is a free, open-source Mac app for cloud storage.

Sign in to your clouds once and they appear in Finder's sidebar. Files download when you open them, and you can mark a folder to keep it on your Mac. The app also has its own browser for moving files between clouds, and it can back up a folder to any cloud on a schedule.

It supports Google Drive, OneDrive, Dropbox, S3, Backblaze, SFTP, WebDAV and about 50 more.

No account, no tracking, no subscription. It is free and will stay free. macOS 15 or later, Apple Silicon and Intel.

Download: https://github.com/CasaVargas/Nimbus/releases/latest

It's a new 1.0, so I'd like to hear what doesn't work for you.

---

## r/cloudstorage

**Title:** Free Mac app to see all your cloud storage in one place and move files between clouds

**Body:**

I wrote Nimbus because I use more than one cloud and wanted to see them together. I'm the author; it is free and open source.

- A Home screen showing how much space is free on each cloud
- Browse any of them, and drag files from one cloud straight to another
- Each cloud can appear in Finder as a drive
- Scheduled backups from your Mac to a cloud, or from one cloud to another, with a preview first
- Optional encrypted folder inside any cloud, so the provider can't read the files

Works with Google Drive, OneDrive, Dropbox, Backblaze B2, S3 and compatibles, pCloud, Box, Mega and many more (anything rclone supports).

No account and no tracking. Mac only, macOS 15 or later.

https://github.com/CasaVargas/Nimbus
