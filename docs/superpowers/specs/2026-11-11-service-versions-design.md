# Version history from the service (#74)

## Goal

In the inspector, list the earlier versions a service kept of a file, and
restore or download one. Only on services where rclone can list them.

## Research (spike, rclone 1.76.0, 2026-11-11)

**Which backends.** rclone exposes old versions as a listing option on three
backends only: `s3` (`versions`, also `version_at`, `version_deleted`), `b2`
(`versions`, `version_at`) and `imagekit` (`versions`). Nothing else has one:

| Service | rclone | v1 |
|---------|--------|----|
| S3 and S3-compatible (AWS, Wasabi, R2, MinIO…) | `versions` option; bucket needs versioning on | **Yes** |
| Backblaze B2 | `versions` option; B2 keeps versions by default | **Yes** |
| ImageKit | `versions` option | No: a media CDN, not tested, rarely a Nimbus cloud |
| Google Drive | no revision listing or restore in rclone (only Google Docs export formats) | No |
| OneDrive / SharePoint | keeps versions, but rclone only offers `no_versions` (delete them), no listing | No |
| Dropbox, Box, pCloud, GCS, Azure Blob, others | no listing option | No |

**How it's requested.** A connection-string override on the configured remote:
`<remote>,versions:` (rclone accepts overrides on named remotes). No new RC
endpoint is needed: `operations/list` on `remote,versions:` with the file's
folder returns the live file plus each old version as a separate entry named
`<base>-vYYYY-MM-DD-HHMMSS-mmm<ext>`, where the stamp is the **UTC time the
version was replaced** and `<ext>` is Go's `path.Ext` of the name (last dot;
a dot file like `.env` puts the whole name in `ext`). `Size` is that
version's size; `ModTime` is its rclone mtime metadata.

Verified against a versioned bucket (moto S3 server, rclone rcd): three writes
of `docs/report.txt` listed as `report.txt` +
`report-v2026-11-11-190948-000.txt` + `report-v2026-11-11-190949-000.txt`;
the same call with `fs: "mini,versions:"` and `remote: "bkt/docs"` (Nimbus's
remote-root form) works too. Without `,versions` only `report.txt` lists.

**Restore.** `operations/copyfile` with `srcFs: "remote,versions:"`,
`srcRemote: <versioned path>`, `dstFs: "remote:"`, `dstRemote: <live path>`
worked: the live file got the old content and the **replaced current file
became a new old version** (`report-v…-190951-000.txt`). So restore
**replaces the live file in place and loses nothing**: the service keeps
what was there as another version. No "save a copy" mode in v1.
The restored file carries the old version's mtime.

**Download.** Same `copyfile` with `dstFs` a local folder works.

**Aliases.** The override applies to the named remote's own backend, so an
`alias` pointing at S3 is not supported in v1 (the raw `type` must be
`s3`/`b2`, not the alias-resolved type).

## Design

- **RcloneKit** (`Versions.swift`):
  - `FileVersion { path, name, savedAt, size }`.
  - `RcloneClient.versionsFs(_ fs:)` — `"r:"` → `"r,versions:"`,
    `"r:bucket"` → `"r,versions:bucket"`, `"r,x=1:"` → `"r,x=1,versions:"`.
  - `FileVersion.parse(name:file:)` — matches rclone's naming for one file.
  - `fileVersions(fs:remote:)` — lists the parent on the versions fs, keeps
    the file's old versions, newest first.
  - `copyVersionAsync(fs:version:dstFs:dstRemote:)` — async `copyfile` from
    the versions fs; returns the job id.
- **App:** `Services/VersionSupport.swift` — allow-list `s3`, `b2` on the raw
  backend type.
- **Inspector:** `FileVersionsRow` under Share, shown only for files on a
  supported cloud: a **Version History…** button opens `FileVersionsSheet`.
  The sheet loads the list (saved date in local time, size), with **Restore…**
  (confirmation: "the current file is kept as an earlier version") and
  **Download…** (folder picker; saved as `name (yyyy-MM-dd HH.mm).ext`). Both
  run as rclone jobs registered with `TransferStore`, so they show in the
  transfer drawer. Empty list → "No earlier versions. Versioning may be off for
  this bucket."

## Out of scope (v1)

- Deleted files (`version_deleted`), point-in-time browsing (`version_at`).
- Deleting old versions; Drive/OneDrive revisions; aliases and crypt over S3/B2.
- The File Provider extension (Finder's "Browse All Versions").

## Testing

- RcloneKit: versions-fs strings; name parsing (ext, no ext, dot file,
  multi-dot, lookalike names); `fileVersions` decodes a mocked listing into
  versions with date and size, newest first; `copyVersionAsync` request params.
- App: `VersionSupport` (s3/b2 yes; sftp, drive, alias no); row visibility
  (files on supported clouds only).
- Manual: restore and download against a versioned bucket.
