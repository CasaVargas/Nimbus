# Task 10 Report: Advanced Pane And Three-Pane Settings Shell

## Scope

- Replaced the legacy six-destination Settings shell with the approved three-pane `SettingsView` (`General`, `Transfers`, `Advanced`) at the 680 x 520 target size.
- Added `AdvancedSettingsView` with rclone path controls, strict version display, daemon status/action handling, restart-required state, and privacy-safe diagnostics actions.
- Moved shared settings services to `NimbusApp` ownership so the Settings shell and main window use the same notification and diagnostics instances.
- Removed the retired top-level Settings panes (`GeneralSection`, `AppearanceSection`, `AboutSection`, `RcloneSection`) once the replacement compiled and passed snapshots.
- Added new shell and Advanced-pane snapshot coverage plus shell contract assertions.

## TDD Record

1. Added `AdvancedSettingsViewTests` and `SettingsViewTests` before any production changes.
2. Ran the focused suite and captured the intended RED compile failure:
   - `cannot find 'AdvancedSettingsView' in scope`
   - missing `diagnosticsService` environment key-path support
3. Implemented the new Advanced pane, service environment plumbing, and three-pane shell.
4. Regenerated the Xcode project, recorded the new snapshot fixtures on the first focused run, visually inspected them, then reran the same focused suite to GREEN.

## Verification

- `xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' -only-testing:NimbusTests/AdvancedSettingsViewTests -only-testing:NimbusTests/SettingsViewTests test`
  - Passed: 6 tests in `Advanced settings` and `Settings shell`.
- `xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' -only-testing:NimbusTests/GeneralSettingsViewTests -only-testing:NimbusTests/TransferSettingsViewTests -only-testing:NimbusTests/DiagnosticsServiceTests test`
  - Passed: 9 tests across the touched dependent suites.
- `xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' test`
  - Expected baseline failure only: `EmptyStateTests.rendersWithCTA()` (`EmptyState-with-cta` perceptual mismatch, 30 bits vs tolerance 8). No new failures from Task 10.
- `xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' build`
  - Passed.
- `git diff --check`
  - Passed.

## Visual Evidence

- Inspected `Settings-Shell.png` and the four new Advanced fixtures:
  - `Settings-Advanced-connected.png`
  - `Settings-Advanced-restart-required.png`
  - `Settings-Advanced-disconnected.png`
  - `Settings-Advanced-error.png`
- The Advanced pane states render with the expected daemon actions and diagnostics controls. The shell fixture shows the new compact window sizing and General-first layout.

## Manual Acceptance

- Live app launch was not executed in this task sandbox.
- Manual evidence is limited to the recorded PNG inspection plus the focused/macOS-hosted snapshot suites above.

## Concerns

- Hosted snapshot capture for `SettingsView` logs AppKit `Invalid view geometry: width is negative.` warnings even though the fixture output is stable and the rerun passes. No visible clipping was present in the inspected PNG, but the warning is worth keeping an eye on if the shell layout changes again.
- The known unrelated full-suite failure remains `EmptyStateTests.rendersWithCTA()` and was intentionally left untouched.
