# Task 9 Report: Transfers Settings Pane

## Delivered

`TransferSettingsView` replaces the previous performance-only transfer section.
It uses separate Performance and Behavior sections with native macOS form rows:

- Concurrent transfers is constrained to 1 through 32 and applies immediately
  through rclone `options/set` with `{"main":{"Transfers":count}}`. It is
  persisted only after rclone accepts the update; existing jobs retain the
  concurrency with which they started, while later operations use the new count.
- Bandwidth is held as a local draft and commits after a valid Return or
  focus-loss event. Nimbus applies the trimmed value with `core/bwlimit` before
  persisting it. Empty means unlimited and is sent to rclone as `off`; an RC
  failure retains the prior persisted/runtime value and displays a nonmodal
  inline error.
- File conflict, notification mode, and history retention bind directly to
  `AppSettings`, so Nimbus applies them immediately through the established
  `NimbusApp` settings observers.
- Enabling a notification mode checks the injected notification service and
  requests authorization only when it is undetermined. The delivery boundary
  also preflights the first qualifying notification, so the fresh-install
  default of Failures Only still requests once before the first failed-transfer
  notification if the picker was never touched. A denied permission retains the
  selected preference and exposes the separately focusable System Settings
  recovery link; request failures remain visible inline and never crash or
  duplicate the terminal transfer handoff.

Every daemon start and retry receives the persisted `--transfers` count and
`--bwlimit` rate (`off` for unlimited), so the next daemon also reflects the
last successfully applied preferences.

`TransferSection` was removed and `SettingsView` now selects the new Transfers
destination.

## Verification

The focused macOS test command passed on 2026-08-25:

```sh
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus \
  -destination 'platform=macOS' \
  -only-testing:NimbusTests/TransferNotificationServiceTests \
  -only-testing:NimbusTests/TransferSettingsViewTests test
```

It ran eleven notification-delivery cases and three hosted pane snapshots. The
fixtures are deterministic dark-Aqua renders at 680 x 520 points:

- `Settings-Transfers.png`
- `Settings-Transfers-invalid-bandwidth.png`
- `Settings-Transfers-notifications-denied.png`

All three PNGs were inspected directly. The invalid state begins at the top of
the Performance section, visibly retains the draft and error, and the denied
state visibly includes both the disabled status and notification-settings
recovery link.

The companion `swift test` run for `RcloneKit` also passed on 2026-08-25,
including the typed `options/set` payload assertion and the RC error-body
handling check for a 200 response that still carries `{ "error": ... }`.
