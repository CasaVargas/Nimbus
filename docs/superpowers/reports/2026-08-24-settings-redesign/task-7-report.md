# Task 7 Report: Rclone Restart, Version, And Diagnostics

## Scope

- Added `activeBinaryPath`, `rcloneVersion`, `restartRequired(for:)`, and explicit `restart(binaryPath:)` lifecycle APIs to `RcloneDaemon`.
- Captures the active binary only after `Process.run()` succeeds and queries `rclone version` off the main actor.
- Added lifecycle generation checks so stopped or superseded startups cannot later publish daemon state. Stale-daemon cleanup runs once per daemon instance, avoiding overlap with a fresh restart.
- Added `DiagnosticsService` with only the approved support fields and a Console launch scoped to `subsystem == "app.casavargas.nimbus"`.
- Regenerated project references for the new service and tests. XcodeGen's unrelated `FileProviderExtension/Info.plist` substitutions were restored.

## TDD Record

1. Added restart-required and diagnostics privacy tests before the production APIs existed.
2. The intended RED invocation could not reach compilation because sandboxed Xcode and SwiftPM cache writes were denied. The tests were not changed after implementation.
3. The first approved focused build exposed an exclusivity error in the `uname` architecture helper. The helper now copies the machine tuple before taking its pointer; the focused suites then passed.

## Verification

- `xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' -only-testing:NimbusTests/DiagnosticsServiceTests -only-testing:NimbusTests/RcloneDaemonSettingsTests test`
  - Passed: 3 tests in 2 suites.
- `git diff --check` passed.
- No full suite was run for this task at the controller's direction. The SDD ledger records the pre-existing `EmptyStateTests.rendersWithCTA()` snapshot mismatch and the full-suite-only `RemoteStatusServiceTests.probeAllRunsInParallel()` flake; neither was touched.

## Self-Review

- Restart requirement is true only for a connected daemon whose active binary differs from the configured binary.
- Stop clears active binary and version state; `restart` always stops before starting with the explicit selected path.
- Diagnostics never include active binary paths, daemon error detail, remote names, rclone config, credentials, local/remote paths, or filenames. Invalid/unexpected rclone version output is rendered as `Unknown`.
- `openLogs()` launches Console with the Nimbus subsystem predicate and does not create a log archive.
