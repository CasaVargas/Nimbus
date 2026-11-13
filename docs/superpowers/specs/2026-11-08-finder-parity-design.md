# Finder Parity — Design

**Date:** 2026-11-08
**Status:** Built 2026-11-08 in three PRs: Keep Downloaded (#18), Copy Share Link (#20), Thumbnails (#21). See "As built" at the end for what was left out and what was never checked live.
**Research:** `docs/superpowers/reports/2026-11-08-competitive-feature-gaps.md`
**Area:** `Nimbus/FileProviderExtension/` mainly, plus RcloneKit and the browser inspector

## Why

People switching from the Dropbox, Google Drive or OneDrive apps, or from Mountain Duck or
ExpanDrive, expect three things in Finder that Nimbus doesn't do today:

1. **Keep a file or folder on this Mac**, and **remove the download** to free space. Every
   competitor in Finder has this. Nimbus always downloads on demand, and nothing can be pinned.
2. **Copy a share link** from Finder's menu. Mountain Duck, Dropbox, Google Drive, odrive and
   Cyberduck all have it. rclone supports it for most popular services.
3. **Thumbnails** for photos in Finder before they're downloaded. The official clients have them.

All three are what someone notices in their first hour after switching. None of them needs a new
screen.

## What the platform and rclone give us (verified 2026-11-08)

- **Content policy.** `NSFileProviderItem.contentPolicy` is declarative per item: `.inherited`,
  `.downloadLazily`, or `.downloadEagerlyAndKeepDownloaded` (macOS 13+). The SDK says an item
  with `.inherited` moved into a keep-downloaded folder is scheduled for download automatically.
  Today `Item.swift` hard-codes `.downloadLazily` on **every** item, which blocks inheritance.
- **Remove Download.** The system already offers it for items it can evict. User-controlled
  eviction is on unless `NSExtensionFileProviderAllowsUserControlledEviction` is false. There is
  no system "Keep Downloaded" field sent to the provider, so pinning has to be Nimbus's own
  action.
- **Custom Finder actions.** These are `NSFileProviderCustomAction.performAction(identifier:
  onItemsWithIdentifiers:)` plus an `NSExtensionFileProviderActions` array in the extension's
  Info.plist. Each action has an `ActivationRule` predicate evaluated against the item, which
  can read `userInfo`.
- **Thumbnails.** `NSFileProviderThumbnailing.fetchThumbnails(for:requestedSize:
  perThumbnailCompletionHandler:completionHandler:)` lives on the same extension; no separate
  target is needed.
- **Share links.**
  - `operations/publiclink` takes `fs`, `remote`, `expire` and `unlink`. It fails clearly on
    backends without support ("... doesn't support public links").
  - `operations/fsinfo` returns `Features.PublicLink` per remote without a network call
    (checked: `local` false, `s3` true).
- **Download and evict from the app.** `NSFileProviderManager.requestDownloadForItem` and
  `evictItem(identifier:)` can be called from the app for the in-app controls.

## Goals

1. **Keep Downloaded** works on files and folders from Finder's menu and from the browser
   inspector. Pinned items download now, stay downloaded, and stay current. **Allow Removing
   Download** undoes it.
2. **Copy Share Link** appears in Finder's menu only for clouds that support links. It puts the
   link on the clipboard and confirms. The inspector gets a fuller version with expiry and Stop
   Sharing where the service supports them.
3. Photos and PDFs show **thumbnails** in Finder without the user opening them, within size and
   cache limits.
4. Nothing regresses for files people don't touch: on-demand stays the default.

## Non-goals

- **Two-way sync, or "keep everything downloaded" for a whole cloud.** Pinning the cloud's root
  folder already gives that.
- **Version history, Spotlight, sync-status badges** beyond what macOS draws. These are later
  phases.
- **Thumbnails from the service** (for example Google Drive's own `thumbnailLink`). rclone doesn't
  expose them over the RC API. Possible later.
- **Video thumbnails.** They would mean downloading large files just to draw an icon.

## 1. Keep Downloaded

### Model

- **`PinStore`**, shared by the app and the extension:
  - A JSON file per domain in the app-group container:
    `group.app.casavargas.nimbus/Pins/<domain>.json`.
  - It holds a set of pinned item identifiers (`"<remote>:<path>"`).
  - Writes are atomic (write to a temp file, then replace). Readers reload on change; a pin set
    is small.
  - Renames and moves through the extension (`modifyItem`) rewrite matching identifiers and any
    descendants with the old path prefix. Deletes drop them.
  - Pins for a remote are removed when the cloud is removed.
- **`FileProviderItem.contentPolicy`** is computed per item:
  - The root container is `.downloadLazily`, which is today's behavior.
  - A pinned item is `.downloadEagerlyAndKeepDownloaded`.
  - Everything else is `.inherited`, so children of a pinned folder are kept too.
- **Pinned items expose `userInfo["pinned"] = true`**, so the Finder actions can choose which
  label to show.

### Finder actions (extension Info.plist)

| Identifier | Title | Shows when |
|---|---|---|
| `app.casavargas.nimbus.keepDownloaded` | Keep Downloaded | Every selected item is unpinned |
| `app.casavargas.nimbus.allowRemovingDownload` | Allow Removing Download | Every selected item is pinned |

`performAction` for these two:
1. Updates the `PinStore`.
2. Calls `signalEnumerator` on each item's parent container and on `.workingSet`, so the system
   picks up the new `contentPolicy`.
3. For newly pinned **files**, calls `requestDownload` as a belt-and-braces measure. The
   download should start from the policy alone; the builder confirms that on a real domain and
   removes the call if it isn't needed.

The system's own **Remove Download** stays available on unpinned items. On a pinned item it
fails with "non-evictable", which is correct.

### In the app

- The browser inspector gets a **Keep on this Mac** switch for a single selection, as in the
  mockup. It writes the same `PinStore` and signals the domain through
  `NSFileProviderManager(for:)`.
- The switch is disabled, with the caption "Show this cloud in Finder to keep files on this Mac",
  when the cloud's File Provider domain isn't enabled.
- The file list's cloud-status column shows a pin glyph for pinned items. It sits next to the
  existing downloaded and cloud-only glyphs.

## 2. Copy Share Link

### RcloneKit

- `publicLink(fs:remote:expire:unlink:) async throws -> URL`, which decodes `{"url": "..."}`.
- `features(fs:) async throws -> RemoteFeatures`, from `operations/fsinfo`. Only `publicLink:
  Bool` is needed now. The type has room for more features later.

### Capability

- The app caches `Features.PublicLink` per remote in the shared app-group defaults, keyed by
  remote name.
- It refreshes the cache on daemon connect and after a cloud is added or edited, alongside the
  `CloudMonitor` refresh.
- The extension reads that cache to set `userInfo["canShare"]` on every item.

### Finder action

| Identifier | Title | Shows when |
|---|---|---|
| `app.casavargas.nimbus.copyShareLink` | Copy Share Link | Exactly one item is selected and `canShare` is true |

`performAction` works like this:
- It calls `publicLink`. No expiry is requested unless the service needs one: S3 and B2 links
  are pre-signed and get the service maximum, 7 days on S3.
- It writes the URL to the general pasteboard.
- It posts a user notification: **"Share link copied"**, with the file name and, when there is
  one, "Expires in 7 days".

**Open question for the builder:** the extension is sandboxed. If writing to `NSPasteboard` or
posting a notification is refused there, fall back to opening
`nimbus://share-link?remote=…&path=…`. The app then does the copy and the notification. Register
the URL scheme only if that fallback is needed.

### Inspector

The **Share** row has three parts:
- **Copy Link**.
- An **Expires** menu: Never / 1 day / 7 days / 30 days. It shows only options the service
  accepts; when the service ignores `expire`, the menu is hidden.
- **Stop Sharing**, which uses `unlink: true`. It shows only for services where rclone supports
  unlink: Dropbox, Google Drive, OneDrive and pCloud (the builder confirms the list).

For clouds without share links the row reads: "<Service> doesn't support share links."

### Errors

All errors are in plain words:
- "<Service> didn't make a link: <first line of rclone's error>".
- An expired sign-in maps to "<Cloud> needs you to sign in again" and points to Home's sign-in
  flow.

## 3. Thumbnails

- `FileProviderExtension` conforms to `NSFileProviderThumbnailing`. Each identifier is handled
  as follows:
  - If the item's type conforms to `.image` or `.pdf` and its size is **≤ 20 MB**, download it
    through the existing `downloadFile` path into a temp file. Build the thumbnail at
    `requestedSize` (ImageIO `CGImageSourceCreateThumbnailAtIndex` for images,
    QuickLookThumbnailing for PDFs), return PNG data, then delete the temp file.
  - Anything else returns `nil` data with no error, and Finder keeps the generic icon.
  - If the item is already downloaded, Finder generates the thumbnail itself; this path is only
    for items that are still in the cloud.
- **Cache:** thumbnails are kept under the domain's state directory
  (`NSFileProviderManager.stateDirectoryURL`), keyed by identifier, item version and requested
  size. The cache is pruned from the oldest entries to stay under **200 MB**. A changed item
  version misses the cache naturally.
- **Limits:**
  - At most 3 thumbnail downloads at a time per domain.
  - Cancellation through the returned `Progress` stops the downloads.
  - These downloads count toward the speed limit, because they go through the same daemon.

## Exit gates

- **Unit tests:**
  - `PinStore`: add, remove, rename a prefix, delete, reload.
  - `contentPolicy` mapping: root, pinned, inherited.
  - Action activation `userInfo`.
  - `publicLink` and `features` request bodies and decoding (RcloneKit mock).
  - Thumbnail eligibility (type × size) and cache key and pruning.
- **RenderPreview** of the inspector's Keep on this Mac and Share rows in all states:
  supported, unsupported, expiry hidden, signed out.
- **Manual check on a real File Provider domain.** Do this on a spare Mac or a clean user
  account. Never on a Mac with real Nimbus domains while using a demo config.
  1. Pin a folder: its files download and survive Remove Download.
  2. Unpin: Remove Download works again.
  3. Copy Share Link on Google Drive and on S3: you get a link that opens.
  4. On SFTP, the action is absent.
  5. A photo folder shows thumbnails before you open it.
- No new compiler warnings, and the full suite is green apart from the known `EmptyState`
  failure.

## Phasing

Each phase is its own PR:

1. **Keep Downloaded:** `PinStore`, content policy, the two Finder actions, the inspector switch.
2. **Copy Share Link:** RcloneKit additions, the capability cache, the Finder action, the
   inspector row.
3. **Thumbnails.**

## Left to the builder

- Whether `requestDownload` is needed after pinning (see section 1).
- The pasteboard and notification fallback from the extension (see section 2).
- Which backends ignore `expire` or support `unlink`. Confirm with rclone 1.76 and hide the
  controls accordingly.
- The exact glyph for "pinned" in the file list. An SF Symbol `pin.fill` at caption size is
  suggested.

## As built (2026-11-08)

All three phases merged the day the spec was written, before the spec itself reached `main` (#45).

Left out on 2026-11-08 and added on 2026-11-10 (inspector only; Finder's action is unchanged):

- **Stop Sharing.** A button under the share row, for services whose rclone backend acts on
  `unlink`.
- **Expiry choices.** Never / 1 day / 7 days / 30 days where the backend acts on `expire`; 1 day
  and 7 days on S3, whose links are pre-signed and capped at a week.

Which services get which control was read from each backend's `PublicLink` in rclone 1.76.0
(`ShareLinkSupport`). Section 2's guess (Dropbox, Google Drive, OneDrive, pCloud for unlink) was
wrong:

| Control | Services |
|---|---|
| Stop Sharing | Gofile, Jottacloud, kDrive, Pixeldrain, Yandex Disk |
| Expiry, all four choices | Dosya, Files.com, Gofile, kDrive, OneDrive, PikPak, Storj |
| Expiry, 1 or 7 days | S3 and compatibles |
| Neither | Everything else, including Google Drive, Dropbox, pCloud, Box, Mega and B2 |

- The lists are allow-lists. A backend that ignores `unlink` answers a Stop Sharing request by
  making a new link, so an unknown backend gets no button.
- B2 lost the expiry menu it had: its links are plain bucket URLs and rclone ignores `expire`.
- Dropbox honours `expire` on paid plans only and rclone drops it without an error on others, so
  it gets no menu rather than a caption that could be false.
- A crypt, combine or other wrapper passes links through but is not resolved to its inner
  service (only aliases are), so it gets neither control.

Never checked in the running app:

- The inspector's Keep on this Mac switch (#18: onboarding was showing).
- The thumbnail cache's location after the EPERM fix (#21).
- The "Share link copied" banner (#20: the test install had no notification permission).
- Share links on a real Google Drive, and the action's absence on SFTP. #20 was checked against a
  local S3 server and an alias cloud only.
- Stop Sharing against a real service. No account on any of the five was available.
