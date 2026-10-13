# Task 5 Fix Round 2

## Scope

- `TransferHistoryFile` decodes a version envelope before its version-specific document schema, preserving future-version files even when their record shape has changed.
- `TransferHistoryWriter` drains a newer queued snapshot after an older write fails, but rethrows when the failed snapshot is still current so it does not retry in a loop.
- The persistence regression test uses a latched first-save continuation and a one-second bounded start wait to prevent its ordering control from hanging.

## Verification

Controller-run focused suites passed on 2026-08-24: 13 tests in 0.012 seconds, including:

- `TransferHistoryFileTests.unsupportedFutureSchemaIsPreservedDuringRestore`
- `TransferStorePersistenceTests.failedOlderSaveDrainsTheNewestQueuedSnapshot`

The full suite is intentionally deferred to the controller.
