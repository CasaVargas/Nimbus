# Encrypted Folder — Design

**Date:** 2026-11-11
**Status:** Draft; decisions below taken in the session that built it (Jon to confirm on the PR).
**Issue:** #68
**Builds on:** #67 (`Lock with Keychain`, opt-in rclone config encryption), `Views/CopySync/LocationPicker`,
`NewRemoteIntegration` (Finder registration used by Add Cloud).

## Why

Nimbus only offers rclone's raw `crypt` form in the Add Cloud picker: six questions, two passwords,
jargon ("filename_encryption", "password2"). Mountain Duck/Cyberduck (Cryptomator), CloudMounter,
odrive and RcloneView have a guided flow. Want: pick a folder, set a password, done. It shows up as
its own place in the sidebar and in Finder.

## Decisions

1. **Where the password lives: in the crypt remote's section of `rclone.conf`, obscured** (rclone's
   own `obscure`), the same as a password typed into the raw crypt form. Not in the Keychain. rclone
   reads crypt passwords only from the config (or env), so a Keychain copy would just be a second
   place to keep in step. What protects it at rest is #67: with **Lock with Keychain** on, the whole
   config, crypt password included, is encrypted with the Keychain key. The sheet says so and, when
   the config is not locked, points at that switch. It does not turn it on itself (that is a
   config-wide migration with its own guards).
2. **No salt (`password2` left empty).** The password alone opens the folder, from any rclone or
   another Mac. A random salt kept only in the config would make a lost `rclone.conf` lose the data
   even when the user remembers the password. Cost: rclone's built-in default salt is shared by every
   such folder, so the password needs to be a real one. Minimum 10 characters.
3. **Defaults otherwise:** `filename_encryption = standard`, `directory_name_encryption = true`
   (rclone's defaults; not written to the config).
4. **Naming:** the crypt remote is the location's name, typed by the user; default
   `"<folder> Encrypted"` (`"<cloud> Encrypted"` at a cloud's root), with characters rclone rejects
   replaced by spaces and ` 2`, ` 3`… added if taken. Same rules as Add Cloud: trimmed, non-empty,
   not already used, plus rclone's own: letters, digits, space, `_ . + @ -`, not starting with `-`
   or a space. Parentheses are rejected (checked on rclone 1.76), hence no `(Encrypted)`.
5. **Placement:** the underlying folder is any folder on any cloud, or a folder on this Mac, picked
   with the same `LocationPicker` as Copy Between Clouds. Its `remote` is `cloud:path`
   (or the absolute local path). The folder is created if missing.
6. **Existing folders:** reconnecting an encrypted folder made elsewhere is the same flow. If the
   folder already has entries and none of them decrypt with the password, setup is undone (the new
   remote deleted) and the sheet says the password is wrong or the folder isn't encrypted. A folder
   whose entries decrypt is accepted.
7. **Entry points:** "New Encrypted Folder…" in the Add Cloud row's context menu and as a chip in the
   Add Cloud picker next to "Import from rclone.conf…". The raw crypt provider stays in the picker
   for people who want the other options.

## Sheet

`SheetChrome` "New Encrypted Folder", 520 wide:

- **Folder:** `LocationPicker` (`.row`). Lead line: "Files are encrypted on this Mac before they're
  uploaded. The cloud only sees scrambled names and contents."
- **Name:** text field, prefilled from the folder until the user edits it; collision/invalid footer.
- **Password / Confirm:** two `SecureField`s; footer for too short / don't match.
- **Warning callout:** "If you forget this password, nobody can recover these files. Not even
  Nimbus." plus a required checkbox "I've saved this password somewhere safe".
- **Keychain note:** when the config isn't locked: "The password is saved, scrambled but not
  encrypted, in rclone.conf. Turn on Settings › Advanced › Lock with Keychain to encrypt it."
- **Create** (primary, ⏎) enabled only when all of the above are valid. While working, a spinner and
  "Creating…". On success: the Finder step of Add Cloud (`NewRemoteIntegration`, honoring "Add new
  clouds to Finder"), refresh the cloud list, dismiss. Finder failures reuse
  `FinderIntegrationWarning`.

## rclone calls

```text
operations/list   fs=<base fs>  remote=<path>          (existing entries; "directory not found" → none)
operations/mkdir  fs=<base fs>  remote=<path>          (only when missing)
config/create     name=<name> type=crypt
                  parameters={remote: "<base fs><path>", password: "<plain>"}
                  opt={obscure: true, nonInteractive: true}
operations/list   fs="<name>:" remote=""               (only when the folder had entries)
config/delete     name=<name>                          (only to undo after a wrong password)
```

`opt.obscure` makes rclone obscure the password itself; without it rclone guesses whether a value
is already obscured. Verified on rclone 1.76 (2026-11-11): a name with spaces works, the config gets
`password = <obscured>` and no `password2`, and `rclone ls ":crypt,remote=…:"` with only
`RCLONE_CRYPT_PASSWORD` set lists the files.

## Code

- `RcloneKit/Remotes.swift`: `createRemote(name:type:parameters:options:)`, `options` sent as `opt`.
- `ViewModels/EncryptedFolderSetup.swift`: `@Observable @MainActor`; validation, default name, the
  call sequence above behind a small protocol so tests can fake rclone.
- `Views/Remotes/EncryptedFolderSheet.swift`; entry points in `RemotesSidebarSection` and
  `ProviderPicker` (`onEncryptedFolder`).

## Tests

- Validation: name rules, collisions, password length/match, acknowledgement; default names.
- Flow with a fake client: creates with `obscure`, mkdirs a missing folder, undoes on undecryptable
  entries, accepts decryptable ones, surfaces rclone errors.
- Live (opt-in, real rclone): create over a scratch local folder, write a file through the crypt
  remote, check the base folder holds only scrambled names, the config has an obscured password and
  no `password2`, and a second setup over the same folder with a wrong password is refused.
- Snapshot of the sheet (empty, filled, not-locked note).

## Not in v1

- "Encrypt this folder" from the browser's context menu.
- Changing the password of an existing encrypted folder (rclone can't re-encrypt in place).
- Filename-encryption options; use the raw crypt form for those.
