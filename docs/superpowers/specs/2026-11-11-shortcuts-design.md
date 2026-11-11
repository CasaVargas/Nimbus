# Shortcuts: App Intents for backups, share links and Keep Downloaded (#69)

## Goal

Nimbus actions in Shortcuts and Spotlight, over features that already ship:

| Intent | Input | Does |
|--------|-------|------|
| **Run Backup** | a saved backup (`BackupEntity`) | Queues it as a manual run (same as Back Up Now). Returns at once. |
| **Copy Share Link** | one file or folder in a Nimbus Finder location | Makes the service's public link, puts it on the clipboard, returns the URL. |
| **Keep Downloaded** | files or folders in a Nimbus Finder location | Pins them (same as Finder's action / the inspector's switch). |
| **Allow Removing Download** | files or folders in a Nimbus Finder location | Unpins them. |

An `AppShortcutsProvider` lists all four so they show in Spotlight and the
Shortcuts gallery without the user building anything.

## Out of scope (v1)

- Stop Sharing, share-link expiry choice (the service's default is used: a week on S3, none elsewhere).
- Waiting for a backup to finish, or returning its summary.
- A CLI or Services menu (the parity report also mentions them).
- Running intents in the File Provider extension: everything runs in the app.

## Design

- **Where:** `Nimbus/Nimbus/Intents/`, in the app target. Intents run in the
  app process (macOS launches Nimbus if it isn't running) and need the app's
  rclone daemon anyway.
- **Dependencies:** `NimbusApp.init` sets `IntentServices.current` (daemon,
  backup store and runner, File Provider bridge, cloud monitor). A plain
  static rather than `AppDependencyManager`: `@Dependency` traps when nothing
  is registered (test hosts), and with no services an intent just fails with
  a sentence.
- **Ready check:** each intent that needs rclone waits up to 20 s for the daemon
  to connect (and for the backup file to load), so an intent that launched
  Nimbus works. Past that it fails with "Nimbus couldn't start its rclone engine."
- **Files → cloud items:** a Shortcuts file must be a real file URL inside a
  Nimbus File Provider location. `NSFileProviderManager.getIdentifierForUserVisibleFile(at:)`
  gives the item identifier and domain; `ShortcutTarget` turns that into
  `(remote, path)` (identifiers are `"<remote>:<path>"`; the root container is
  path `""`). Anything else fails with "“name” isn't in a Nimbus cloud in Finder."
  Mounted (NFS) volumes are not resolved in v1.
- **Run Backup refusals** map `BackupRunner.Refusal` to plain sentences
  (not approved yet → "Preview it in Nimbus once before it can run."; already
  running; backups file read-only; unknown backup).
- **Copy Share Link** refuses the cloud's top folder and clouds whose service
  makes no links (`CloudMonitor` capability), with the same wording as the inspector.

## Testing

- Unit: `ShortcutTarget` parsing, refusal messages, `BackupEntityQuery` over a
  store, share-link expiry choice per backend.
- Build check: the app bundle's `Metadata.appintents` lists the four intents.
- Manual: run each from Shortcuts against a live cloud.
