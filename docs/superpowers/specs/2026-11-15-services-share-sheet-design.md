# Services Menu and Share Sheet — Design

**Date:** 2026-11-15
**Status:** Draft, waiting on Jon's approval. Nothing is built.
**Issue:** none yet (README "Not done yet": "Services menu and Share Sheet").
**Builds on:** `Views/CopySync/` (`LocationPicker`, `FolderBrowserSheet`), `State/TransferStore.swift`,
`State/AppRouter.swift`, `Interaction/QuickLookHost.swift` (`downloadToTemp`),
`FileProviderExtension/AppWaker.swift`, `Shared/AppGroup.swift`.

## Why

Getting a file into a cloud from another app means switching to Nimbus or Finder and
dragging. Getting one out of the Nimbus browser to Mail, Messages or AirDrop means downloading
it first by hand. macOS has standard places for both: the Services menu and the Share Sheet.
Cyberduck and Transmit are in the first; nothing in the parity report is in the second.

## Today

- No `NSServices`, no share extension, no `NSSharingServicePicker` or `ShareLink` anywhere.
- The app is **not sandboxed**; the rclone daemon runs as the user and can read any local path.
- The browser has no "upload local files" path of its own. Local-to-cloud copies exist only in
  Copy Between Clouds (`LocationPicker` handles local folders) and Backups.
- Copy Share Link exists (Finder action, inspector, Shortcuts). Sharing the *link* is covered.
- One extension target today (File Provider). The release workflow signs it and checks that
  its version and architectures match the app's.

## Decision

Three entry points, one destination sheet.

1. **Send to Nimbus sheet (in the app).** Given a list of local files, it asks for a cloud and
   a folder (the existing `LocationPicker` / `FolderBrowserSheet`), remembers the last
   destination, and starts copies that appear in Transfers like any other. Everything below
   funnels into it.
2. **Services menu: "Send to Nimbus…"** for files and folders selected in any app (Finder's
   right-click > Services included). Declared in the app's Info.plist; no new target.
   macOS launches Nimbus if it isn't running.
3. **Share Sheet, inbound: a "Nimbus" share extension.** It appears in other apps' Share
   menus for files, images, URLs-to-files and text. It is deliberately thin: it stages what
   it was given and hands off to the app, which shows the Send sheet.
4. **Share Sheet, outbound: "Share…"** in the browser's context menu and the inspector for
   one or more selected files. Nimbus downloads them to a temp folder (as Quick Look does),
   then shows the system share picker. Folders are not offered. Copy Share Link stays where
   it is.

## Send to Nimbus sheet

```
┌─ Send to Nimbus ─────────────────────────────┐
│  3 items · 14.2 MB                           │
│  report.pdf, IMG_2041.heic, notes.txt        │
│                                              │
│  To   [ Google Drive ▾ ]  [ /Inbox      … ]  │
│                                              │
│                       [ Cancel ]  [ Send ]   │
└──────────────────────────────────────────────┘
```

- Opens in the main window through a new `AppRouter.Route.send(SendRequest)`.
- Send starts one `operations/copyfile` per file and one `sync/copy` per folder, each added
  to `TransferStore` with a new source kind `.sendToNimbus`.
- A name that already exists at the destination is not overwritten silently: the sheet
  lists the clashes and offers Replace or Keep Both (suffix " 2").
- No clouds yet: the sheet says so and offers Add Cloud.
- Last destination is remembered in `AppSettings`.

## Share extension

- New target `ShareExtension` (`app.casavargas.nimbus.Share`), sandboxed, app group
  entitlement, no RcloneKit, no Sparkle. Activation rule: files, images, file URLs, plain
  text; up to 100 items.
- For each item: a file URL the app can read is passed by path; anything else (a photo from
  Photos, a text selection, a file the sandbox only lent to the extension) is copied into
  `<group container>/ShareInbox/<uuid>/`.
- It writes `manifest.json` there, opens `nimbus://send?inbox=<uuid>`, and completes the
  request. The app reads the manifest, shows the Send sheet, uploads, and deletes the inbox
  folder when the transfers finish or the sheet is cancelled. Inbox folders older than a
  day are swept at launch.
- The extension shows no UI beyond a brief "Opening Nimbus…".

## Approaches considered

| | What | Trade-off |
|---|---|---|
| **A. Thin extension, app does the work (chosen)** | Extension stages and hands off; one Send sheet serves Services, Share and drops | The user lands in Nimbus instead of staying in the share popover. One picker, one transfer path, transfers visible in Transfers |
| B. Full extension | Cloud and folder picker inside the share popover; the extension uploads through the daemon itself | Stays in place, but duplicates the picker in a sandboxed target, must wake the app to get a daemon (`AppWaker`), and its uploads would bypass `TransferStore` |
| C. Services only, no extension | Skip the Share Sheet inbound | No new target or release work, but Photos, Safari and most modern apps only offer Share, not Services |

## Phasing

- **PR 1 (no new target):** Send sheet, Services menu, outbound Share…, `nimbus://` URL
  scheme. Shippable alone.
- **PR 2:** the share extension, plus release work: sign it in `package-release.sh`, add it
  to the version and architecture check in `release.yml`, restore its Info.plist after
  `xcodegen generate` the way the File Provider one is.

## Not in this change

- Uploading by dragging Finder files onto the browser (worth doing; it would reuse the Send
  path, but it is its own change).
- Sharing a link from the Share picker (Copy Share Link covers it).
- Services *provided by other apps* acting on files selected in Nimbus.
- Share extension on a Mac where Nimbus has no clouds yet beyond the "Add Cloud" prompt.

## Risks

- **Privacy prompts.** The app reading a path in Desktop, Documents or Downloads triggers the
  macOS folder-access prompt once. Staged copies avoid it; direct paths don't.
- **Staging doubles disk use** for large items the extension has to copy. Capped: over 2 GB
  staged in one share, the extension refuses with a message to use Services or drag instead.
- **Services registration** only refreshes when the app is in `/Applications` and has been
  launched; the live check must use an installed build.

## Tests

- `SendRequestTests`: manifest round trip, clash detection, Keep Both naming, folder vs file
  call selection.
- `SendSheetSnapshotTests`: filled, clashes, no clouds.
- `ShareInboxTests`: staging layout, sweep of stale inboxes, the 2 GB cap.
- `ServicesProviderTests`: pasteboard file URLs become a `SendRequest`.
- Live: Finder > Services > Send to Nimbus…; Share from Preview and Photos; Share… from the
  browser to Mail.
