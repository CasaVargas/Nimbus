# Feature parity — Nimbus 0.10.1 against comparable Mac apps (2026-11-11)

**Status:** Draft for review.
**Supersedes the gap table in:** `2026-11-08-competitive-feature-gaps.md` (its recommendations
1 and 2, Finder parity and Backups, have shipped).

**Question:** Now that Keep Downloaded, share links, Finder thumbnails and scheduled backups are
in a signed release, where does Nimbus match, lead and trail the apps people compare it to?

**Short answer:** Nimbus has closed the two biggest gaps from three days ago and now matches or
beats every Finder-mount app on Keep Downloaded, share links and thumbnails, and every rclone
front-end on backup safety. Five gaps are left that more than one competitor fills:

1. **Search** — nothing in the app, nothing in Spotlight.
2. **Encrypted folders** — only the raw rclone crypt form.
3. **Sign-ins in the Keychain** — tokens are still plain text in `rclone.conf`.
4. **Automation** — no Shortcuts, no command line of its own.
5. **Setup friction** — Nimbus needs `brew install rclone`; no competitor asks for a
   prerequisite.

## How to read the tables

- **Yes / Partial / No** are backed by a vendor page, vendor docs, a release note or (for Nimbus)
  the code on `main` at `f1ffff7`.
- **?** means no vendor source said either way. It does not mean the feature is missing.
- Checked 2026-11-11. Sources are listed at the end, per app.

## Nimbus today (0.10.1)

Shipped since the 2026-11-08 report:

- **Keep Downloaded / Allow Removing Download** from Finder's menu and the inspector.
- **Copy Share Link** in Finder and the inspector, with expiry and Stop Sharing where the service
  supports them.
- **Finder thumbnails** for photos and PDFs still in the cloud.
- **Backups:** saved jobs, hourly/daily/weekly schedule, a preview before the first run, exclude
  lists, a versions folder with pruning, a removal limit, catch-up after sleep.
- **Changes made elsewhere reach Finder** (within about ten minutes).
- Home, menu bar panel, the Stratosphere look, an "On this Mac" column.

Confirmed absent in the code (grep on `Nimbus/`, `FileProviderExtension/`, `RcloneKit/`):

- No search field anywhere, no Core Spotlight.
- No App Intents, no Services menu, no CLI.
- No Keychain calls and no rclone config password.
- No crypt setup flow (crypt appears only as a provider tile).
- No `sync/bisync`, no `operations/check`.
- No File Provider decorations (Finder badges are whatever macOS draws).
- No provider version history (backups keep their own versions folder).
- No tabs or dual pane.
- No update check (by design: the README promises no update pinging).

## 1. Apps that put clouds in Finder

MD = Mountain Duck 5.4, ED = ExpanDrive, CM = CloudMounter 4.18, od = odrive.
Official = the Dropbox, Google Drive and OneDrive clients.

| Feature | Nimbus | MD | ED | CM | od | Official |
|---|---|---|---|---|---|---|
| Price | Free, GPL-3.0 | One-time per major version; App Store $59.99/yr | Free for personal use; $29/mo per 10 seats for business | $29/yr or $74 lifetime | $200 per user per year; no free tier | Client free, storage paid |
| Finder mechanism | File Provider, NFS option | File Provider, NFS | File Provider | "Native" mount, macFUSE, network drive | Sync folder with placeholder files | File Provider |
| Services | About 70 (rclone) | 19 protocols | 15 | 12 | 24 | Own only |
| Downloads on demand | Yes | Yes | Yes | Yes | Yes | Yes |
| Keep offline / remove download | Yes | Yes | Partial (pin; removal not documented) | Partial (one mount type only) | Yes (paid) | Yes (Drive: removal ?) |
| Sync badges in Finder | Partial (system-drawn only) | Yes | ? | ? | Yes | Yes (Drive: cloud icon only) |
| Share link from Finder | Yes | Yes | ? | Partial (Drive, Box) | Partial (made in the web client) | ? |
| Link expiry / stop sharing | Yes, where the service allows | Expiry yes; revoke not documented | ? | ? | ? | ? |
| Spotlight | **No** | Partial (File Provider mode) | Yes (vendor claim) | ? | ? | OneDrive yes; Drive downloaded files only |
| In-app search | **No** | No (bookmark filter) | ? | ? | ? | Drive yes |
| Encrypted folders | **Partial** (raw crypt form) | Yes (Cryptomator) | No | Yes (AES-256) | Yes (paid) | ? |
| Sign-ins in the Keychain | **No** | Partial (vault passwords confirmed) | Yes | Yes | Partial | ? |
| Thumbnails for files still in the cloud | Yes (photos, PDFs) | No (downloaded files only) | ? | ? | ? | OneDrive yes; Drive no |
| Version history | Partial (backup versions only) | Yes | Partial | ? | Partial (backup copies) | ? |
| Scheduled backups | Yes | No | No | ? | Partial (automatic, no schedule) | Drive: mirror a folder |
| Preview before a run | Yes | No | No | ? | No | No |
| Exclude filters | Yes (backups) | Partial (name patterns) | No | ? | No | ? |
| Two-way folder sync | No (held) | Partial (cache only) | No | ? | Yes | Yes |
| Speed limit | Yes | ? | ? | ? | Partial | Dropbox, Drive yes |
| Transfer list and history | Yes | Yes (last 20 files) | ? | Yes (activity log) | ? | Drive yes |
| Menu bar, open at login | Yes | Yes | ? | ? | Tray yes | Yes |
| Shortcuts / CLI | **No** | Partial (separate `duck` CLI) | No on macOS | ? | Yes (CLI) | ? |
| Own browser window | Yes | No | ? | ? | Web client | Web |
| Cloud to cloud | Yes (server-side where rclone can) | ? | Partial (through the Mac) | Partial (through the Mac) | ? | n/a |
| Storage across all accounts | Yes | Partial (per volume) | ? | ? | ? | Own account only |

**Reading it:** Nimbus is the only app in this group with a preview-gated scheduled backup, a
cross-account storage view and expiring links, and one of two confirmed to draw thumbnails for
files that are still in the cloud. It trails on search, encryption, the Keychain and badges.

## 2. rclone front-ends

RV = RcloneView 1.6.8, RUI = Rclone UI 3.7.5, RCM = RClone Manager 0.3.5,
RG = `rclone gui` (rclone 1.76, out of beta 2026-11-06).

| Feature | Nimbus | RV | RUI | RCM | RG |
|---|---|---|---|---|---|
| Price / licence | Free, GPL-3.0 | Free; Plus $19.80/yr; lifetime $99.80; closed | Free; paid from $7; Apache-2.0 | Free, GPL-3.0 | Free, inside rclone |
| UI | Native SwiftUI/AppKit | ? | Tauri + React | Tauri + Angular | Browser tab |
| Reuses `rclone.conf` | Yes | Yes | Yes | ? | Yes |
| Finder mount | File Provider, NFS | macFUSE, NFS option | Yes (mechanism ?) | macFUSE | Yes (mechanism ?) |
| Keep offline, thumbnails, Finder menu | Yes | No (no File Provider) | No ("not planned") | No | No |
| Share links | Yes, with expiry and stop | ? | Yes (no expiry) | ? | ? |
| Search | **No** | ? | Yes | Partial (filter) | ? |
| Encrypted folders | **Partial** | Yes (crypt UI) | ? | Partial | ? |
| Config protected | **No** | Partial (config password) | Partial (encrypted config) | Partial (settings vault) | ? |
| Scheduled jobs | Yes (while Nimbus is open) | Yes (paid tier) | Yes (OS scheduler, app can be closed) | Yes (cron) | ? |
| Preview before a run | Yes, required on first run | ? | ? | Partial (dry-run flag) | ? |
| Versions kept, removal limit | Yes | Partial (keep last N) | ? | ? | ? |
| Two-way sync | No (held) | Partial (beta) | Yes | Yes | ? |
| Compare two folders | **No** | Yes | ? | ? | ? |
| Speed limit, transfer history | Yes | ?, yes | ?, yes | Yes, yes | ?, yes |
| Menu bar, open at login | Yes | Yes | Yes | Menu bar yes | No |
| Automation | **No** | Partial (terminal, chat bots in Plus) | Partial (command bar) | Partial (webhooks, headless) | Yes (rclone CLI and RC) |
| Dual pane / tabs | No | Yes | Dual pane | Tabs | ? |
| Storage overview | Yes, across clouds | ? | ? | Yes | Yes, per remote |

**Reading it:** nothing else built on rclone uses File Provider, and Rclone UI has said it won't.
That is still the moat. The new fact is `rclone gui` leaving beta: a free, bundled front-end now
ships with every rclone install, so "a GUI for rclone" is no longer a reason to pick Nimbus. The
Finder integration and the backup safety rails are.

Where the front-ends lead: schedules that run with the app closed (Rclone UI), two-way sync,
folder compare, and a crypt UI.

## 3. File managers and transfer apps

CD = Cyberduck 9.6, TX = Transmit 5 (Transmit 6 noted), FL = ForkLift 4.7, C1 = Commander One 3.18.

| Feature | Nimbus | CD | TX | FL | C1 |
|---|---|---|---|---|---|
| Price / licence | Free, GPL-3.0 | Free, GPL | $45 once; $24.99/yr on the App Store | $19.95 or $34.95 once | Free; PRO $29.99 |
| Services | About 70 | About 15 protocols | 4 protocols + 11 clouds | 12 protocols | 3 protocols + 9 clouds |
| Finder mount | Yes | No (Mountain Duck is separate) | No in 5; 6 brings Transmit Disk back | ? | Partial |
| Share links | Yes | Yes (11 providers, S3 expiry) | Partial | Partial (Dropbox) | Partial (Dropbox, Drive) |
| Search remote files | **No** | Yes | Partial (current folder) | Yes | Yes |
| Encrypted folders | **Partial** | Yes (Cryptomator) | ? | ? | Yes |
| Sign-ins in the Keychain | **No** | Yes | Yes | Yes | ? |
| Scheduled jobs | Yes | No | No in 5; 6 adds them | Partial (saved, schedule ?) | ? |
| Preview before sync | Yes | Yes | ? | Yes | ? |
| Two-way sync / compare | No | Partial (mirror) | ? | Yes | ? |
| Version history | Partial | Yes | ? | ? | ? |
| Speed limit, queue | Yes | Yes | Yes | Yes | Queue yes |
| Automation | **No** | Partial (`duck`) | Partial; 6 adds Shortcuts | Partial | Partial |
| Dual pane / tabs | No | Tabs | Both | Both | Both |
| Quick Look | Yes | Yes | Yes | Yes | Yes |
| Edit in another app | ? (not checked live) | Yes | Yes | Yes | Partial |
| S3 metadata (class, ACL, headers) | No | Yes | Partial | ? | ? |
| Storage overview | Yes | Partial (folder size) | ? | Partial | ? |

**Reading it:** this group wins on search, the Keychain and power-user S3 work. Transmit 6 (beta
closed, release pending, macOS 26 only) adds a File Provider disk, scheduled syncs and Shortcuts,
which moves it from "transfer app" into Nimbus's lane.

## Scorecard

**Ahead (no competitor matches the combination):**
- File Provider on top of about 70 services, free and open source.
- Backups that show what they will do first, keep what they replace, and stop at a removal limit.
- Share links with expiry and Stop Sharing from Finder.
- Thumbnails for files still in the cloud (only OneDrive is confirmed to do this).
- One storage view across every cloud.

**At parity:** on-demand files, Keep Downloaded, speed limit, transfer history, menu bar, open at
login, cloud-to-cloud copies, Quick Look.

**Behind, and it matters:**

| Gap | Who has it | Why it matters | rclone / macOS path |
|---|---|---|---|
| Search | Cyberduck, ForkLift, Commander One, Rclone UI; Spotlight in Mountain Duck, ExpanDrive, OneDrive | The most common thing to do with files after opening them | Recursive list with a filter; Spotlight through File Provider still needs a live check |
| Encrypted folders | Mountain Duck, Cyberduck, CloudMounter, odrive, Commander One, RcloneView | Privacy is part of the pitch | One-click `crypt` over any cloud |
| Keychain | ExpanDrive, CloudMounter, Cyberduck, Transmit, ForkLift | Tokens in plain text is the one item a security-minded reviewer will flag | Config encryption plus `--password-command` |
| Automation | odrive CLI, `duck`, Transmit 6 Shortcuts, rclone itself | Very "Mac"; cheap once jobs exist | App Intents: run a backup, copy a share link |
| rclone prerequisite | Every competitor installs in one step | First-run drop-off | Offer to download rclone on first launch, or document the trade-off |

**Behind, lower weight:**
- Finder badges of Nimbus's own (File Provider decorations).
- Backups that run with Nimbus closed (Rclone UI uses the OS scheduler).
- Compare two folders (`operations/check`).
- Provider version history (uneven across backends).
- A visible "Verified" after uploads.
- Remote changes in Finder take about ten minutes.

**Deliberately not chasing:** two-way sync, dual pane, S3 metadata editing, mobile companion,
chat-bot control. Reasons are unchanged from the 2026-11-08 report.

## Recommended order

1. **Find anything** — in-app search across all clouds first (nobody offers cross-cloud search),
   then Spotlight if the live check passes.
2. **Privacy** — Keychain-backed config password, then the Encrypted Folder flow. Do the Keychain
   first: it's a security fix and the encryption flow stores a password too.
3. **Shortcuts** — "Run backup", "Copy share link", "Keep downloaded".
4. **Trust polish** — Finder badges, "Verified" after uploads, compare two folders.
5. **Setup** — decide whether Nimbus fetches rclone itself.

## Issues

| Gap | Issue |
|---|---|
| Search across clouds | #65 |
| Spotlight | #66 |
| Keychain | #67 |
| Encrypted folder | #68 |
| Shortcuts | #69 |
| rclone prerequisite | #70 |
| Finder badges | #71 |
| Backups with Nimbus closed | #72 |
| Compare two folders | #73 |
| Version history | #74 |
| "Verified" after uploads | #75 |
| Faster remote changes | #76 |

## README corrections made with this report

- "Not done yet" listed scheduled syncs and public link management; both shipped in 0.10.0.
- "How it compares": ExpanDrive's pricing and mount mechanism, Mountain Duck's protocol count and
  App Store subscription, and `rclone gui` leaving beta.

## Limits of this research

- Many cells for the official clients, CloudMounter and Commander One are **?** because help
  pages returned errors or didn't cover the feature.
- UI technology is mostly unstated by vendors.
- Transmit 6 details come from MacGeneration and heise, not Panic.
- Mountain Duck's NFS claim rests on a search snippet of a Cyberduck blog post.
- Nimbus "edit in another app" was not checked live.

## Sources

**Mountain Duck:** mountainduck.io; docs.mountainduck.io (`/connect/integrated/`, `/connect/sync/`,
`/share/`, `/versions/`, `/preferences/`, `/issues/`, `/protocols/`);
apps.apple.com/us/app/mountain-duck/id1024974133

**ExpanDrive:** expandrive.com (`/pricing/`, `/mac`); docs.expandrive.com (`offline-access.md`,
`security.md`, `how-expandrive-works.md`, `pricing-and-licenses.md`)

**CloudMounter:** cloudmounter.net; cloudmounter.net/cloud-mounter-purchase.html;
cloudmounter.net/faq/types-of-drive-mouting-used-in-cloudmounter/; apps.apple.com/app/id1130254674

**odrive:** odrive.com (`/pricing`, `/features`); docs.odrive.com (`manage-disk-space`,
`backup-to-any-storage`, `odrive-encryption-encryptor`, `odrive-cli`)

**Dropbox:** help.dropbox.com (`/installs/macos-support-for-expected-changes`,
`/sync/make-files-online-only`, `/installs/bandwidth`)

**Google Drive:** support.google.com/drive/answer/10838124, `/12178485`, `/16631477`, `/2375081`

**OneDrive:** support.microsoft.com "Save disk space with OneDrive Files On-Demand for Mac"

**Cyberduck:** cyberduck.io; docs.cyberduck.io (`/cyberduck/browser/`, `/sync/`, `/share/`,
`/info/`, `/protocols/s3/`)

**Transmit:** panic.com/transmit; help.panic.com/transmit/transmit5/; help.panic.com/transmit/transmit-beta/;
macg.co (2026-05, Transmit 6 beta); heise.de/-11311407

**ForkLift:** binarynights.com (`/store`, `/manual`); blog.binarynights.com

**Commander One:** commander-one.com; apps.apple.com/us/app/commander-one-pro-ftp-cloud/id1035237815

**RcloneView:** rcloneview.com (`/src/pricing`, `/support/howto/`)

**Rclone UI:** rcloneui.com/docs/ui (`schedules`, `commander`, `operations/mount`,
`operations/share`); github.com/rclone-ui/rclone-ui (issue 18 for File Provider)

**RClone Manager:** github.com/Zarestia-Dev/rclone-manager (README, releases)

**rclone gui:** rclone.org/gui/; rclone.org/commands/rclone_gui/; rclone.org/changelog/
