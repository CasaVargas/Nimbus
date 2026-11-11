# Keychain-locked rclone.conf (#67)

## Problem

Sign-in tokens and access keys sit in plain text in `rclone.conf`. ExpanDrive,
CloudMounter, Cyberduck, Transmit and ForkLift keep them in the Keychain. A
security-minded reviewer flags this first.

## Decision

**Opt-in, off by default** (option 2 of the triage). A switch in
Settings > Advanced encrypts `rclone.conf` with rclone's own config encryption,
using a random password kept in the login Keychain.

- Off by default keeps the README promise ("keep using the `rclone` command
  line") for everyone who doesn't turn it on, and nobody's config is rewritten
  behind their back.
- Turning it on for fresh installs (option 3) is a later, one-line default
  change once the switch has been used for a while. It is not in this PR.

## How the password moves

Nimbus never holds the password in memory after creating it, and it never
appears in any argv or environment.

- **Store.** A generic-password item in the login Keychain: service
  `app.casavargas.nimbus`, account `rclone-config`, label `Nimbus rclone config`.
  The value is 32 random bytes, base64.
- **Created by `/usr/bin/security`, not by `SecItemAdd`.** An item the app makes
  itself is owned by the app's partition and ACL, so `security` reading it later
  shows a Keychain password prompt every time rclone starts. An item made by
  `security` trusts `security`. Nimbus runs `security -i` and writes the
  `add-generic-password … -w <password>` line to its **stdin**, so the password
  is never on a command line (`ps` can't see it).
- **Handed to rclone** as
  `RCLONE_PASSWORD_COMMAND=/usr/bin/security find-generic-password -s app.casavargas.nimbus -a rclone-config -w`
  in the environment of every rclone child: `rclone rcd` (RcloneDaemon) and
  `rclone serve nfs` (MountManager). rclone runs it only when it meets an
  encrypted config; on a plain config it is never called (verified with rclone
  1.76), so it is always set. A value the user already exported wins.
- **File Provider extension:** nothing. It only talks to the daemon over HTTP.
- `rclone rcd`'s stdin is `/dev/null`, so an encrypted config with no usable
  password fails fast instead of hanging on a password prompt.

Verified by hand with rclone 1.76 before writing this:
`config encryption set --password-command …` and `… remove` both run without a
TTY; `rcd` with the env var reads the encrypted file and writes it back
encrypted after `config/create`; a missing Keychain item on a plain config is
harmless.

## Turning it on

1. Refuse while any network drive (NFS) is connected or a transfer or backup is
   running: their rclone processes loaded the plain config and would write it
   back in plain text the next time a token refreshes. The switch is disabled
   with a one-line reason.
2. Stop the daemon.
3. Locate the config with `rclone config file`.
4. Create the Keychain item if it is missing; reuse it if present (never
   overwrite: an old encrypted backup may need it).
5. Copy `rclone.conf` to `rclone.conf.nimbus-backup` (mode 0600).
6. `rclone config encryption set --password-command <cmd>`.
7. Verify the first line is `# Encrypted rclone configuration File`. On success
   delete the backup (it is plain text, which is the thing we're removing). On
   failure restore the backup and show the error.
8. Start the daemon again.

## Turning it off

Same guards, then `rclone config encryption remove --password-command <cmd>`,
with the same backup/verify/restore around it (the backup here is encrypted, and
is deleted on success). The Keychain item stays: it is harmless, and turning the
switch back on reuses it.

## State shown

Read from the file, not from a preference: the config's first line is the
source of truth.

| File | Keychain item | Switch | Note |
|---|---|---|---|
| plain or missing | any | off | — |
| encrypted | present | on | CLI snippet shown |
| encrypted | missing | off, disabled | "rclone.conf is locked with a password Nimbus doesn't have." |

The daemon's error for the last row, when `rcd` exits during startup, says the
same thing instead of "Rclone process exited unexpectedly".

## Settings UI

New section in Settings > Advanced, after **rclone**:

- **Title:** Saved sign-ins
- **Row:** "Lock with Keychain" switch, with an inline spinner while it migrates.
- **Footer (off):** "Sign-ins are saved in rclone.conf as plain text, where the
  rclone command line can read them."
- **Footer (on):** "Sign-ins in rclone.conf are encrypted with a key in your
  Keychain. To use the rclone command line, set:" plus the
  `RCLONE_PASSWORD_COMMAND` line in monospace and a **Copy** button.
- Turning it on or off restarts the connection engine; the footer says so while
  it runs.

## README

- Line 29: the CLI promise gains "(if you lock sign-ins with the Keychain, the
  command line needs one environment variable; see below)".
- New short "Sign-ins and the Keychain" section with the export line.
- Roadmap line 115 drops "sign-ins kept in the Keychain".

## Tests (NimbusTests)

- Keychain round trip against the real login Keychain under a test-only
  service name: create, exists, read via the password command, delete; a second
  create reuses the first password.
- Encryption round trip against a real rclone on a scratch `--config` file:
  enable → header present, no `access_key_id`/`token` lines, backup gone,
  `listremotes` works with the env var; disable → plain text back. Opt-in via
  `NIMBUS_LIVE_RCLONE`, like `BackupLiveTests`.
- Child environment: `RcloneEnvironment.childEnvironment` adds the password
  command, keeps an existing user value, and never contains the password.
- State table: plain / encrypted+key / encrypted+no key.

## Out of scope

- On by default for fresh installs (follow-up decision).
- The Encrypted Folder flow — it should reuse this Keychain helper.
- Users who encrypted `rclone.conf` themselves with their own password: shown as
  "encrypted, no Nimbus key"; Nimbus doesn't ask for their password.
