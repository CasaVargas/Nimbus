# Task 7 Fix Round 1

## Scope

- `RcloneDaemon` retains one shared stale-daemon cleanup task and awaits it before every launch, so a restart cannot spawn a daemon while initial cleanup is still enumerating or terminating prior-session processes.
- Health-check retries revalidate the lifecycle identity after each delay and before the terminal failure transition, preventing a superseded start from overwriting a replacement start's state.
- `DiagnosticsService` emits only the canonical numeric rclone version token `v<major>.<minor>.<patch>`. Pre-release, build, malformed, and additional-text suffixes are intentionally excluded and reported as `Unknown`.
- Deterministic DEBUG-only startup hooks suspend cleanup and retry delays for the lifecycle regressions without adding a release-build test seam.

## Verification

Controller-run focused Task 7 suites passed on 2026-08-25: 7 tests, 9 parameter cases, 0 failures.

- `RcloneDaemonSettingsTests.restartWaitsForInitialStaleDaemonCleanupBeforeLaunching`
- `RcloneDaemonSettingsTests.supersededStartCannotSetFailureAfterFinalRetryDelay`
- `DiagnosticsServiceTests.diagnosticTextIncludesStrictNumericRcloneVersions`
- `DiagnosticsServiceTests.diagnosticTextRejectsNonSemanticRcloneVersion`

The full suite was not run.
