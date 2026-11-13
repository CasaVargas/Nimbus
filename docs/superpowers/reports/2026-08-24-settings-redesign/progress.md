# SDD ledger — plan: docs/superpowers/plans/2026-08-24-settings-redesign.md

Branch base: 829a2dbefae6af2672c14432933734fd51eb8121
Baseline: 130/131 tests pass. EmptyStateTests.rendersWithCTA is an existing 30-bit snapshot mismatch.
Ruling: Proceed with the known EmptyState-with-cta baseline mismatch — it reproduces on untouched main and is outside this spec — cost if wrong: a Settings change could indirectly affect global snapshot rendering and be missed, so focused snapshots plus build remain mandatory and no unrelated fixture may be updated.

## Preflight Interface Scan

| Tasks | Producer / consumer | Finding |
|---|---|---|
| 1 → 2 | AppSettings mount defaults → MountDraft | Consistent: creation-only read; edit values win. |
| 1 → 3 | Finder default → NewRemoteIntegration | Consistent: post-create side effect only. |
| 1 → 4 | ConflictPolicy preference → CopyRequest | Consistent: explicit initializer, per-operation mutation preserved. |
| 1 → 5 | History retention → TransferStore persistence | Consistent: Task 5 consumes stable enum. |
| 1 → 6 | Notification mode → notification service | Consistent: Task 6 consumes stable enum. |
| 1 → 8 | General preferences → General pane | Consistent. |
| 1 → 9 | Transfer preferences → Transfers pane | Consistent. |
| 1 → 10 | Binary path and services → Advanced/shell | Consistent. |
| 3 → 10 | New integration service → app environments | Consistent; NimbusApp wiring is finalized in Task 10. |
| 5 → 6 | TransferRecord → notification delivery | Consistent: notifications receive terminal records. |
| 5 → 9 | Retention behavior → Transfers pane | Consistent: pane updates AppSettings; TransferStore observes/applies through app wiring. |
| 6 → 9 | Authorization status → notification controls | Consistent: injected service owns OS API. |
| 7 → 10 | Daemon/diagnostics APIs → Advanced pane | Consistent. |
| 8 → 10 | General pane → three-tab shell | Consistent; legacy panes removed only after replacement exists. |
| 9 → 10 | Transfers pane → three-tab shell | Consistent. |
| 10 → all | Final shell and NimbusApp wiring → all services | Consistent; final task is integration gate. |

## Per-Task Consistency

| Task | Tests vs implementation / files | Finding |
|---|---|---|
| 1 | Defaults and round trips cover all new stored values | Clean. ConflictPolicy is reused from the existing module. |
| 2 | Draft tests cover create and edit precedence | Clean. |
| 3 | Enabled/disabled/partial integration behavior | Clean; retry UI is part of sheet integration. |
| 4 | Explicit policy initializer and override | Clean. |
| 5 | Persistence, pruning, corruption, active exclusion, UUID identity | Clean; broad ID migration is required to prevent restored/live job collisions. |
| 6 | Policy delivery and authorization boundary | Clean. |
| 7 | Restart-required state and privacy-safe diagnostics | Clean. |
| 8 | General normal/error snapshots and cache behavior | Clean. |
| 9 | Validation and notification-denied snapshots | Clean. |
| 10 | Advanced states, three-tab shell, full/manual gates | Clean. |

Task 1: minor (deferred): AppSettings header comment still says UserDefaults.standard instead of injected defaults (standard by default).
Task 1: complete (commits 829a2db..8b0b258, review clean)
Task 2: fix round 1/5 (1 addressed, 0 open — missing RED evidence supplied; no tracked commit)
Task 2: complete (commits 8b0b258..be586f7, review clean)
Task 3: fix round 1/5 (2 addressed, 1 open — persisted Finder opt-out and inline retry UI fixed; reconnect regression coverage remained)
Task 3: fix round 2/5 (1 addressed, 0 open — AppSettings reload and production reconnect-selector regression added)
Task 3: complete (commits be586f7..c49ed40, review clean)
Task 4: complete (commits c49ed40..7277e07, review clean; specified behavioral test was baseline-green because required initializer arity is compile-time-only)
Task 5: fix round 1/5 (3 addressed, 2 open — serialized/coalesced writes, live retention wiring, and expanded corruption/version/retention tests; future-schema classification and failed-write draining remained)
Task 5: fix round 2/5 (2 addressed, 0 open — envelope-first version handling and latest-snapshot draining after failed save)
Task 5: complete (commits 7277e07..96ec832, review clean; focused persistence suites 13/13)
Task 6: minor (deferred): authorization-status mapping and requestAuthorization false/error forwarding lack configurable-spy behavioral coverage.
Task 6: complete (commits 96ec832..ee218ab, review clean; focused suites pass, RemoteStatus parallel probe flaked in full suite but passed isolated)
Task 7: fix round 1/5 (3 addressed, 0 open — serialized stale cleanup/start, guarded superseded final retry, strict numeric version diagnostics)
Task 7: complete (commits ee218ab..06f3b1b, review clean; focused suite 7 tests plus 9 parameter cases)
Task 8: fix round 1/5 (3 addressed, 0 open — truthful owned FinderSync metadata boundary, deterministic window-backed snapshots, clear-failure regression)
Task 8: complete (commits 06f3b1b..95e9bb5, review clean; two consecutive focused runs 3/3 and fixtures visually inspected)
Task 9: fix round 1/5 (3 addressed, 1 open — live RC performance settings, denied-link accessibility, top-aligned invalid fixture; fresh-install notification prompt remained)
Task 9: fix round 2/5 (1 addressed, 0 open — delivery-boundary authorization preflight for default failures-only mode)
Task 9: minor (deferred): picker and first-delivery authorization requests do not share an in-flight request gate; macOS is expected to collapse duplicate sheets.
Task 9: complete (commits 95e9bb5..939f9e4, review clean; RcloneKit 32 tests, runtime/settings 17 tests, notification/settings 14 tests)
Task 10: complete pending commit (three-pane shell + Advanced pane shipped; focused shell/advanced suites 6/6, dependent settings/diagnostics suites 9/9, full build green, full test run only the documented EmptyState-with-cta baseline mismatch)
