# Competitive feature gaps — research (2026-11-08)

**Question:** Which features do comparable Mac cloud apps have that Nimbus is missing, and
which of them matter?

**Short answer:** Nimbus is already ahead on three things nobody else combines: File Provider
integration, rclone's ~70 backends, and a one-time GPL licence. It is behind on six things
that most competitors treat as table stakes:

1. Keep offline / free up space
2. Share links
3. Search
4. Scheduled backups with a preview of what will change
5. Encrypted folders
6. Thumbnails and versions in Finder

There is also a security gap: sign-in tokens sit in plain text in `rclone.conf`, where
competitors use the Keychain.

## What was compared

- **Apps that put clouds in Finder:** Mountain Duck 5, ExpanDrive, CloudMounter, odrive, and the
  official Dropbox, Google Drive and OneDrive clients.
- **rclone front-ends:** RcloneView, Rclone UI, RClone Manager, and rclone's own `rclone gui`
  (v1.74). Rclone Browser has been dead since 2020.
- **Mac file managers and transfer apps:** Cyberduck 9.6, Transmit 5 and the Transmit 6 beta,
  ForkLift 4.7, Commander One 3.18, and Path Finder.

Sources were vendor pages, changelogs and release notes from 2025–2026, plus App Store, forum
and Reddit complaints. Two research agents gathered them, and every non-trivial claim carries
its source URL in their reports. Unverified claims are marked as such and left out of the
conclusions below.

## Nimbus today (main @ 782d63a)

- **Clouds:** about 70 rclone backends.
  - Guided Add Cloud: tiles, browser sign-in, rclone's own question flow.
  - Signing in again, importing `rclone.conf`, editing, removing.
  - Aliases resolve to the service they point at.
- **Finder:** a File Provider domain per cloud that downloads on demand. NFS network drives are
  the advanced option.
- **Window:**
  - Home overview with storage bars and plain-language status.
  - Per-cloud volume pages.
  - Browser: list/grid, Quick Look, inspector, rename/delete/new folder, drag between clouds
    and to Finder, bookmarks.
- **Moving data:**
  - One-off copy, sync and move between clouds.
  - Transfers with progress, history, notifications and stop.
  - Speed limit, copies at once, and conflict choice.
- **Always on:** menu bar companion, open at login, a status probe every 10 minutes.

Confirmed absent in the code:
- The File Provider items are always `downloadLazily`. There's no pinning, no thumbnail
  extension, no custom Finder actions, and no decorations.
- None of these rclone RC calls is used: `operations/publiclink`, `operations/check`, search.
- No scheduler and no saved jobs.
- No crypt UI.
- No config encryption or Keychain storage.
- No Shortcuts / App Intents.

## Gap table

"Competitors" counts only verified sources.

| Feature | Who has it | Nimbus | rclone support | Weight |
|---|---|---|---|---|
| **Keep offline / free up space** in Finder | All Finder apps (Mountain Duck, ExpanDrive, CloudMounter, odrive, Dropbox, Drive, OneDrive) | Missing; always on demand | n/a (File Provider content policy) | **Table stakes** |
| **Share link** (Finder menu + in app, optional expiry) | Mountain Duck, Cyberduck, odrive, Dropbox, Drive, Transmit (S3 signed URLs) | Missing | `operations/publiclink` (with `expire` where the backend supports it) | **Table stakes** |
| **Search**: Spotlight for cloud files, plus in-app search | Spotlight: Mountain Duck, ExpanDrive, Google Drive (macOS 26). In-app remote search: ForkLift, Commander One | Missing | listing with filters (`operations/list` + `--include`), backend search where it exists | **Table stakes**. No one offers *cross-cloud* search, which is an opening |
| **Scheduled backups / saved jobs** | RcloneView, Rclone UI, RClone Manager, Transmit 6, odrive (Backup beta) | Missing (cut from the Home spec for lack of a scheduler) | `sync/copy`, `sync/sync`, plus Nimbus scheduling | **High**; it was in the approved mockup |
| **Preview before running** (dry run, adds/updates/deletes) | RcloneView, ForkLift | Missing | `_config: {DryRun: true}` on sync calls | **High**; sync deletes files |
| **Filters** (exclude/include, saved presets) | RcloneView, ForkLift, Transmit (File Rules) | Missing | `_filter` on sync calls | Medium |
| **Versioned backups** (keep overwritten or deleted files) | RcloneView ("Automatic Backup", keep last N) | Missing | `--backup-dir` / `--suffix` | Medium; makes backups safe |
| **Encrypted folders** (client-side) | Mountain Duck and Cyberduck (Cryptomator), CloudMounter (AES-256), odrive, RcloneView (crypt UI) | Only the raw crypt backend form | `crypt` backend over any cloud | **High**; privacy is part of the pitch |
| **Credentials in the Keychain** | CloudMounter (documented), Cyberduck, Transmit 6 (Secure Enclave) | Tokens in plain-text `rclone.conf` | Config encryption + `--password-command` | **High (security)** |
| **Thumbnails in Finder** for cloud files | Dropbox, Drive, OneDrive, Mountain Duck (Quick Look) | Missing (Quick Look only inside Nimbus) | File Provider thumbnail extension + range reads | Medium |
| **Version history / restore** | Mountain Duck and Cyberduck (S3 versions), Dropbox, Drive, OneDrive | Missing | Backend-specific (`--s3-versions`, B2 versions, Drive revisions limited) | Medium; uneven across backends |
| **Compare two folders** (checksum) | RcloneView, ForkLift | Missing | `operations/check` | Medium |
| **Upload checksum verification shown to the user** | Cyberduck 9.6, Mountain Duck 5.4 | rclone verifies, but Nimbus doesn't show it | Built into rclone transfers | Low effort, trust win |
| **Shortcuts / App Intents, CLI** | Transmit 6 (Shortcuts), Cyberduck (`duck`), odrive CLI | Missing | — | Medium; very "Mac" |
| **Two-way sync (bisync)** | RClone Manager, ForkLift, RcloneView (experimental) | Missing | `sync/bisync` (rclone marks it advanced) | **Hold**. Risky, and File Provider already covers the "same files everywhere" case |
| Dual pane, tabs | ForkLift, Transmit, Commander One | Single pane | — | Low; Finder plus File Provider covers it |
| S3 metadata (storage class, ACL, headers) | Cyberduck, Transmit | Missing | `operations/settier`, backend commands | Low for this audience |
| Mobile companion, remote-daemon control, Slack/Discord alerts | RcloneView, Rclone UI, RClone Manager | Missing | — | Out of scope (anti-goal: power-user plumbing) |

## Where competitors are weak

- **Pricing has turned against users.**
  - odrive ended its free tier on 2026-03-31; plans are now $200 per user per year.
  - CloudMounter and Mountain Duck sell subscriptions on the Mac App Store.
  - ExpanDrive is free, but only because a SaaS company owns it.
  - A one-time-purchase, open-source app has a clear story here.
- **Reliability complaints repeat:**
  - Mountain Duck: 100–300% CPU, keeping the Mac awake, large trees stuck "pending" for hours.
  - CloudMounter: files that showed as uploaded but never arrived, and no progress bar.
  - Nimbus can lead on this by showing honest transfer state and verified uploads.
- **No rclone GUI uses File Provider.** RcloneView, Rclone UI and RClone Manager all need macFUSE.
  RcloneView is closed source, which users on the rclone forum object to.
- **Nobody offers cross-cloud search in the app**; the only search across clouds is Spotlight.

## Recommendation

Do these as phases, in this order. Each is one PR-sized spec.

1. **Finder parity**
   - Keep offline / Free up space (File Provider content policy plus the Finder menu).
   - **Copy Share Link** as a custom Finder action and an inspector button, through
     `operations/publiclink`.
   - Finder thumbnails.
   - This is what people notice first after switching from Dropbox or Google Drive.
2. **Backups**
   - Saved jobs with a schedule, a preview before the first run ("Will copy 1,204 files, delete
     3"), simple exclude filters, and "keep replaced files" (`--backup-dir`).
   - This restores the cut "Back up your Desktop" suggestion and the Backups section from the
     Home mockup.
3. **Find anything**
   - Search across all clouds in the app (unique), plus Spotlight through File Provider where
     macOS allows it.
4. **Privacy**
   - "Encrypted folder" as a one-click setup over any cloud, using rclone crypt.
   - Move rclone config secrets behind a Keychain-stored password (`--password-command`).
   - The Keychain item is also a correctness fix: the Add Cloud spec already had to retract a
     false "your sign-in is in the Keychain" claim.
5. **Automation and trust**
   - App Intents (Shortcuts: "Back up folder", "Copy share link").
   - Compare two folders.
   - A visible "Verified" after uploads.

**Hold or skip:**
- Two-way sync, until backups prove out. File Provider already gives "same files everywhere".
- Dual pane.
- S3 metadata editing.
- Mobile companion, remote-daemon control, and chat-app alerts. These are power-user plumbing
  that fights the ease-of-use goal.

## Open questions before any of this is specced

- **Keep offline:** which macOS File Provider API does this need on macOS 15–27
  (`contentPolicy`, `.allowsContentPolicyChange`), and does Finder show "Keep Downloaded"
  without a custom action? Verify on a real domain.
- **Share links:** which backends Nimbus users actually have support `operations/publiclink`
  with `expire`? Drive, Dropbox, OneDrive, S3/B2 (pre-signed) and pCloud do; SFTP doesn't.
- **Spotlight:** is it reachable for a third-party File Provider on macOS 26–27, or is it
  Google-only through a private path? Google's v116 notes tie it to macOS 26.
- **Config encryption:** how do the File Provider extension and the app share the config
  password? Both start rclone clients against one daemon, so the daemon could be the only one
  that needs it.
