# Google Drive: Your Own Client ID — Design

**Date:** 2026-11-15
**Status:** Approved 2026-11-15 (Jon: "build the in-app fix"). Built.
**Issue:** none.
**Builds on:** `ViewModels/ReconnectFlow.swift`, `State/CloudSummary.swift` (Home suggestions),
`RcloneKit/ConfigSession.swift`, `Services/RcloneDaemon.swift`.

## Why

Google Drive folders in Nimbus intermittently fail with "The request timed out". The cause,
found on 2026-11-15 with a logging test daemon: Google answers rclone's **shared client ID**
with `403 RATE_LIMIT_EXCEEDED`, rclone backs off (1 s, 2 s, 4 s, 8 s, 16 s…), and RcloneKit
gives up at 30 s. The first Drive listing on a fresh daemon took 16.4 s after five 403s.
OneDrive is unaffected. The rclone CLI lists the same Drive root in under a second when the
quota happens to be free.

rclone 1.76 also prints, for every such remote: "This remote uses rclone's shared Google Drive
client_id, which is being retired and will stop working during 2026."

Nimbus creates Drive remotes on the shared ID on purpose (`RemoteSetupFlow` answers
`config_shared_client_id` with "true") to keep Add Cloud one click. So every Nimbus user with
Google Drive has both problems, and nothing in the app told them: the daemon's stderr went to
`/dev/null`.

## Decision

1. **Tell the user and give them the fix.** Home shows a suggestion for each signed-in Drive
   cloud on the shared ID: "<name> uses a shared Google sign-in", with **Set Up…**. It can be
   dismissed like any other suggestion.
2. **A setup sheet** lists the Google Cloud Console steps, links to the console and to rclone's
   guide, and takes a client ID and client secret. **Save and Sign In** writes only those two
   keys to the remote, then hands straight to the existing sign-in-again flow, because the old
   token belongs to the shared ID.
3. **Listings wait instead of failing.** The browser's listing timeout goes from 30 s to 120 s,
   and after 8 s the loading state says "Still loading", naming the shared sign-in when that is
   the cloud's situation.
4. **rclone's output is kept.** stderr goes to `~/Library/Logs/Nimbus/rclone.log`, capped at
   1 MB (the older half is dropped).
5. **Add Cloud stays one click.** New Drive clouds still start on the shared ID and get the
   suggestion. Asking every new user for a Google Cloud project before they see a file is worse
   than nudging them afterwards.

## Less friction (added 2026-11-15, after Jon set his own up)

Jon's first run through it showed where the five minutes go, so four things were added:

1. **Drop Google's file.** Step 4 ends with Download JSON; dropping that file on the sheet (or
   Choose File…) fills both fields. Only a Desktop app client (`"installed"`) is accepted; a
   Web application client is refused with a sentence saying why.
2. **A link per step,** each to its own console page, instead of one general link.
3. **The "Access blocked" page is explained in the sheet.** It appears when the consent screen
   is in Testing and the account isn't a test user, which is what happened on the first try.
4. **One client ID for every Drive cloud.** Other Drive clouds on the shared ID are listed with
   checkboxes, ticked by default. Save writes the pair to each, then the sign-in sheets run one
   after another. If a save fails part-way, the clouds already saved still get their sign-in.

Also fixed: the Home suggestion stayed after saving, because Home read a config snapshot that
only reloads every ten minutes. Saving now reloads it.

Why not a Nimbus-owned client ID after all: the `drive` scope is restricted, so verification
needs a paid yearly security assessment; `drive.file` is free but only sees files the app
created; an unverified client is free but capped at about 100 users.

## Approaches considered

| | What | Trade-off |
|---|---|---|
| **A. Guide users to their own ID (chosen)** | Suggestion, sheet, longer wait, log | Free and survives the retirement; costs each user about five minutes in Google Cloud Console |
| B. Nimbus ships its own client ID | One click stays for everyone | Drive's restricted scope needs Google verification: money, time and an annual review. Not compatible with a free app without Jon's say-so |
| C. Only soften the symptom | Longer timeout and a "still loading" state | Does nothing when the shared ID is retired |

## Details

- **Detection** (`SharedGoogleClientID.isUsed`): type `drive`, and no `client_id`,
  `service_account_file` or `service_account_credentials`. Read from the config Nimbus already
  loads (`config/dump`); no extra call.
- **Validation:** both fields required; the client ID must end in
  `.apps.googleusercontent.com`. Whitespace is trimmed.
- **The write** is `config/update` with `nonInteractive: true` and only the two parameters.
  Verified on rclone 1.76 against a scratch config: the keys are saved before rclone asks its
  first question (`*oauth-confirm`), which is left unanswered.
- **If the user saves and then abandons the sign-in,** the cloud should keep working until its
  current access token expires (under an hour), then shows the normal "Needs sign-in" state.
  Signing in finishes the job. Not rolled back automatically.
- **The consent screen must be published.** Left in Testing, Google expires the grant every
  seven days. The sheet says so in step 3.
- **Suggestion order:** backups first, then the shared sign-in, then storage tips; still two at
  most. A cloud that needs sign-in gets that banner instead.

## Not in this change

- A Nimbus-owned client ID (approach B).
- The same warning in the cloud's Settings tab or the sidebar.
- Raising the timeout for the folder picker, Send to Nimbus's clash check or the File Provider
  extension. They still give up at 30 s.
- Showing `rclone.log` in Diagnostics.
- Google Photos and Google Cloud Storage remotes (rclone prints no such warning for them).

## Tests

- `SharedGoogleClientIDTests`: detection, validation, the save writes only the pair, slow-notice
  wording, the listing timeout, the log's cap and stderr capture, a snapshot of the sheet.
- `CloudSummaryTests`: the suggestion appears, is dismissible, waits for sign-in, and outranks
  storage tips.
- Live: the suggestion and sheet on a real shared-ID Drive cloud; `rclone.log` contains the
  shared-ID notice. Jon saved a real client ID and signed in on a personal Drive cloud. The file
  drop, the per-step links and the several-clouds pass are covered by tests only.
