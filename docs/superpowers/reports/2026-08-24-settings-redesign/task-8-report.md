# Task 8 Fix Report

## Local Storage Boundary

The General settings pane now reports and clears only Nimbus-owned Finder sync
metadata. The root is resolved through the app-group entitlement:

`FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.app.casavargas.nimbus")/FileProviderSync`

`SyncSnapshotStore` creates only the following descendants beneath that root:

`<FileProviderSync>/<remoteName>/<sha256(containerIdentifier)>.json`

Each JSON file stores a `ContainerSnapshot`: a directory listing baseline of
item identifiers, names, types, sizes, modification times, and a sync-anchor
version. It is safe to remove because the File Provider extension seeds or
rebuilds the snapshot from the next enumeration. Clearing it resets local
change-detection state only; it never removes cloud objects.

Nimbus does not scan or delete Finder's system-managed materialized files.
It also does not include the extension's temporary download staging directory
(`FileManager.default.temporaryDirectory/app.casavargas.nimbus.FileProvider`),
which is non-durable and is owned by the extension's lifecycle cleanup.

The UI therefore calls this data "Finder Sync Data" and explains that Finder
manages materialized cloud files separately.

## Snapshot Stability

`SnapshotHelpers.assertHostedSnapshot` now captures through a retained,
non-key, borderless AppKit window with a fixed dark-Aqua appearance, black
background, no shadow, and two display passes separated by a main-run-loop
turn. Reusing the window prevents the second hosted capture from racing native
control setup while avoiding key-window focus and active-control tint.

The General fixtures use a fixed dark appearance and a launch-at-login service
whose initial system refresh is disabled. The production service still refreshes
by default; the redundant view `onAppear` refresh was removed.

Both `Settings-General.png` and `Settings-General-cache-error.png` were
re-recorded and visually inspected. The cache-error fixture retains the
Application and Finder sections, their toggles and pickers, and the Local
Storage error state.

## Regression Coverage

`clearCacheFailureReportsErrorWithoutSuccessUsage` verifies that a throwing
sync-data clear transitions usage to `.failed`, preserves the error message,
and ends the clearing state instead of reporting stale successful usage.

## Verification

Two consecutive non-record focused runs passed with all three General settings
tests passing in each run.
