# Phase 2c — State Accuracy & Carry-Forward Cleanup

**Date:** 2026-05-15
**Status:** Approved
**Type:** Implementation spec
**Parent specs:**
- `docs/superpowers/specs/2026-05-14-nimbus-north-star-design.md` (strategic)
- `docs/superpowers/specs/2026-05-15-phase2b-supporting-polish-design.md` (predecessor)
- `docs/superpowers/specs/2026-05-15-phase2b-exit-gates.md` (carry-forward source)

> Inserted mini-phase between Phase 2b and the strategic doc's Phase 3 (system integration). Wraps up the state-accuracy and correctness debt accumulated through Phase 2a / 2b before any new feature area begins.

## Goal

Wrap up the five carry-forwards from Phase 2b that make the existing screens *correct* and *live* — without introducing new feature areas. Eliminate the two CRITICAL items from the Phase 2b exit-gate doc so that no future caller of the affected state lands on a broken substrate.

## Scope

### In scope

1. **Critical — NimbusApp mountConfig fix.** Replace direct `mountManager.mount(remote:mountPoint:readOnly:)` calls in `NimbusApp.startApp()` with `mountManager.mountConfig(_:)` so `mountedIDs` stays consistent with `OnboardingView`'s auto-mount path.
2. **Critical — CopySync NimbusError migration.** `CopySyncViewModel.error: String?` becomes `error: NimbusError?`; `CopySyncView` renders `error.message`.
3. **Live remote-status discovery.** `RemoteStatusService` (new) drives per-remote `operations/about` probes on RemotesView appear; `RemoteRow.status` reads real `.connected` / `.authNeeded` / `.error(reason:)` instead of hardcoded `.connected`. Reconnect button retries a single row.
4. **Real `MountManager.refreshAll()`.** Replace the no-op with `cleanupStaleMounts()` + `NSFileProviderManager.getDomainsWithCompletionHandler` reconciliation against `MountConfigStore.configs`. Called on app launch and Mounts view appear.
5. **Real File Provider materialized/evicted queries.** `FileProviderBridge.isItemMaterialized` / `wasRecentlyEvicted` replaced with real `NSFileProviderManager.materializedItemsEnumerator` / `evictedItemsEnumerator` queries behind a per-folder 5s `TimedCache`.

### Out of scope (deferred)

- **Browser `NSOutlineView` AppKit bridge** — moved to Phase 2d "Browser perf." Strategic-doc Risk section flagged this explicitly; substantial AppKit bridging work that warrants its own phase.
- **`RcloneSection` Version + Restart Daemon rows** — blocked on `RcloneDaemon` exposing version + `restart()` APIs. Re-add when those APIs land.
- **OAuth re-authentication flow on Reconnect** — Phase 4. Reconnect in 2c just re-runs the probe.
- **Quota display on Remote rows / Inspector** — `operations/about` returns quota too; we ignore that field in 2c. Display would be feature creep.

### Sequencing

Approach A — criticals first, then features:

1. NimbusApp mountConfig fix
2. CopySync NimbusError migration
3. Live remote-status discovery
4. Real `MountManager.refreshAll()`
5. Real FP materialized/evicted queries
6. Phase 2c exit verification + exit-gate doc

Each task has self-contained build + test gates. Per-task commits.

## Architecture

### Two criticals — pure refactors

No new types, no new services. Just call-site changes:

- **Task 1 (NimbusApp mountConfig):** `NimbusApp.startApp()` lines ~81-89 — `try? await mountManager.mount(remote: cfg.remote, mountPoint: cfg.mountPoint, readOnly: cfg.vfsMode == .readOnly)` becomes `try? await mountManager.mountConfig(cfg)`. The mountConfig method already exists and is the path used by `OnboardingView.attemptAutoMount`.
- **Task 2 (NimbusError migration):** `CopySyncViewModel.error` type changes from `String?` to `NimbusError?`. The internal `catch` block wraps `error.localizedDescription` as `NimbusError(message:)`. `CopySyncView`'s `messageVerbatim:` argument becomes `viewModel.error?.message ?? ""`. The `clearError()` method body is unchanged (still sets `error = nil`).

### Task 3 — RemoteStatusService (new)

```
RemoteStatusService                       // new file: Nimbus/Nimbus/Services/RemoteStatusService.swift
├── @Observable @MainActor final class
├── statuses: [String: RemoteStatus]       // keyed by remote name (no trailing colon)
├── init(client: RcloneClient)
├── func probe(_ name: String) async       // single-row refresh (Reconnect + initial)
├── func probeAll(_ names: [String]) async // parallel TaskGroup
└── func clear(_ name: String)             // called when a remote is deleted

RemoteStatus                              // existing enum, add .unknown case
├── .unknown                              // NEW — before first probe completes
├── .connected
├── .authNeeded
└── .error(reason: String)
```

`NimbusApp` constructs `RemoteStatusService` after `RcloneDaemon` connects and injects it via `.environment(_:)`. `RemotesView.task` fires `statusService.probeAll(viewModel.remoteNames)` on appear. `RemoteRow` reads `statusService.statuses[remote.name] ?? .unknown`. Reconnect context-menu item calls `statusService.probe(remote.name)`. `RemotesViewModel.delete(name:)` calls `statusService.clear(name)`.

#### Auth-failure classification

`RcloneRCError+AuthFailure` (new extension on the existing error type):

```swift
extension RcloneRCError {
    var isAuthFailure: Bool {
        // HTTP 401 / 403, or message contains "oauth" / "token" / "unauthorized" / "forbidden"
    }
}
```

Probe classification:

```swift
do {
    _ = try await client.about(remote: "\(name):")
    statuses[name] = .connected
} catch let error as RcloneRCError where error.isAuthFailure {
    statuses[name] = .authNeeded
} catch {
    statuses[name] = .error(reason: error.localizedDescription)
}
```

### Task 4 — MountManager.refreshAll real implementation

`MountManager.refreshAll()` (currently a no-op):

```
refreshAll()
├── await cleanupStaleMounts()       // existing — sweeps mount(8) NFS mounts
├── domains = try await NSFileProviderManager.getDomainsWithCompletionHandler
├── fpConfigs = configStore.configs.filter { $0.backend == .fileProvider }
└── reconcileFPDomains(domains, fpConfigs, &mountedIDs)
```

`reconcileFPDomains(_:configs:mountedIDs:)` is extracted as a pure free function in `MountManager.swift` so it can be unit-tested without touching `NSFileProviderManager`:

```swift
struct FPDomainInfo { let displayName: String; let identifier: String }

func reconcileFPDomains(
    _ domains: [FPDomainInfo],
    configs: [MountConfig],
    mountedIDs: inout Set<String>,
    logger: (String) -> Void = { _ in }
) {
    for domain in domains {
        if let config = configs.first(where: { $0.id == domain.identifier }) {
            mountedIDs.insert(config.id)
        }
    }
    for config in configs where !domains.contains(where: { $0.identifier == config.id }) {
        logger("FP config \(config.id) has no domain — not auto-recreating")
    }
}
```

Called from `NimbusApp.startApp()` (after the initial auto-mount loop) and `MountsView.task`.

### Task 5 — Real FP materialized/evicted queries

`FileProviderBridge.isItemMaterialized` / `wasRecentlyEvicted` get a real implementation behind a small generic cache:

```
TimedCache<Key: Hashable, Value>           // new file: Nimbus/Nimbus/Services/TimedCache.swift
├── final class — NOT a struct (caches need reference semantics for invalidation)
├── init(ttl: Duration)
├── subscript(key: Key) -> Value?         // returns nil if expired
├── func store(_ value: Value, for key: Key)
└── func invalidate(_ key: Key)
```

`FileProviderBridge` holds a `TimedCache<URL, [URL: Bool]>` per query type (materialized + evicted), keyed by parent directory URL, 5-second TTL. On cache miss:

```swift
func isItemMaterialized(at url: URL) async -> Bool {
    let parent = url.deletingLastPathComponent()
    if let cached = materializedCache[parent] {
        return cached[url] ?? false
    }
    do {
        let enumerator = try NSFileProviderManager.default.materializedItemsEnumerator
        var result: [URL: Bool] = [:]
        // walk enumerator, collect Bool for each child
        materializedCache.store(result, for: parent)
        return result[url] ?? false
    } catch {
        return false  // path likely outside any FP domain
    }
}
```

`materializationDidChange` notifications (if posted on the current macOS) invalidate the relevant parent cache entry; otherwise TTL handles it.

## Data flow

### App launch
```
NimbusApp.startApp()
├── start RcloneDaemon
├── wait for daemon.status == .connected
├── construct RemoteStatusService(client: daemon.client) and inject
├── existing initial auto-mount loop → now mountConfig(_:) (Task 1)
└── await mountManager.refreshAll() (Task 4)
```

### RemotesView appears
```
RemotesView.task
└── await statusService.probeAll(viewModel.remoteNames)
    └── TaskGroup over names → parallel probes → fills statuses[name]
    
RemoteRow body
└── statusService.statuses[remote.name] ?? .unknown → StatusBadge render
```

### MountsView appears
```
MountsView.task
└── await mountManager.refreshAll() (idempotent — Task 4)
```

### Browser row visible
```
Row body
└── await fileProviderBridge.isItemMaterialized(at: url) (Task 5)
    └── cache hit (<5s) → return cached
    └── cache miss → query enumerator, populate cache, return
```

### Reconnect button on RemoteRow
```
Button("Reconnect") → statusService.probe(remote.name)
```

### Remote deletion
```
RemotesViewModel.delete(name:)
├── existing config removal
└── statusService.clear(name)
```

## Error handling

| Failure | Strategy | UI surface |
|---------|----------|------------|
| Task 1 `mountConfig` throws | `try?` swallow (same as today's `mount(...)` call) | Mounts screen badge picks up error |
| Task 2 CopySync operation throws | wrap as `NimbusError(message: error.localizedDescription)` in VM `catch` | EmptyState renders `error.message` |
| Task 3 probe HTTP 401 / 403 / token error | classify via `isAuthFailure` → `statuses[name] = .authNeeded` | StatusBadge "Auth needed", Reconnect CTA |
| Task 3 probe other error | `statuses[name] = .error(reason: error.localizedDescription)` | StatusBadge "Error", tooltip with reason |
| Task 4 `getDomainsWithCompletionHandler` throws | log + leave mountedIDs untouched; next call retries | not surfaced — best-effort reconciliation |
| Task 4 `cleanupStaleMounts` throws | swallowed (existing behavior) | not surfaced |
| Task 5 `materializedItemsEnumerator` throws / path outside FP domain | catch → return `false`, cache the false | no badge — correct semantic |

Status enum on `RemoteRow` IS the error surface for Task 3 — no NimbusError wrapping needed there.

## Testing

New test suites at exit:

| Suite | Tests | Surface |
|-------|-------|---------|
| `RemoteStatusServiceTests` | 8 | mock RcloneClient → probe / probeAll / clear |
| `RcloneRCErrorAuthFailureTests` | 3 | classifier extension |
| `ReconcileFPDomainsTests` | 4 | pure function — domain match / orphan / config without domain / empty |
| `TimedCacheTests` | 3 | hit within TTL / miss after TTL / invalidate clears |

Total new: **+18 tests**. Phase 2c exit target: **≥ 105 tests in 20 suites**.

Tasks 1 / 2 add no tests (call-site changes covered by build + 87 baseline).
Tasks 4 / 5 cover OS-touching paths via build + manual smoke; unit tests only exercise the extracted pure logic.

### Manual smoke (⏳ in exit-gate doc)

- Remotes view: rows show spinner → real status pills after probes complete.
- Trigger auth failure (revoke OAuth on a remote) → `.authNeeded` surfaces; Reconnect retries one row.
- Quit app mid-mount, relaunch → `refreshAll()` picks up the existing NFS mount and FP domain.
- Browse FP-mounted directory → materialized/evicted badges reflect actual file state.

## Implementation order

1. **Task 1 — NimbusApp mountConfig fix** (~0.5d)
2. **Task 2 — CopySync NimbusError migration** (~0.5d)
3. **Task 3 — Add `.unknown` to RemoteStatus + RcloneRCError+AuthFailure extension + tests** (~0.5d)
4. **Task 4 — RemoteStatusService implementation + tests** (~1d)
5. **Task 5 — Wire RemoteStatusService into NimbusApp / RemotesView / RemoteRow / RemotesViewModel** (~1d)
6. **Task 6 — `reconcileFPDomains` pure function + tests** (~0.5d)
7. **Task 7 — `MountManager.refreshAll()` real implementation + wire into startApp / MountsView** (~1d)
8. **Task 8 — `TimedCache` + tests** (~0.5d)
9. **Task 9 — `FileProviderBridge.isItemMaterialized` / `wasRecentlyEvicted` real impl + cache wiring** (~1d)
10. **Task 10 — Exit verification + exit-gate doc** (~0.5d)

Estimated 7 days serial. Test count rises 87 → 105.

## Phase 2c exit gates

| Gate | Target |
|------|--------|
| All baseline tests still green | 87 → 87 |
| New tests pass | +18 |
| Lints | both green |
| `Package.resolved` unchanged | no new SPM deps |
| `RemoteRow` shows real status | ✅ no `.connected` hardcoded |
| Reconnect retries one row | ✅ |
| `MountManager.refreshAll` surfaces stale + FP mounts | ✅ |
| `FileProviderBridge` materialized/evicted accurate | ✅ |
| Two CRITICAL Phase 2b carry-forwards resolved | ✅ |
| Manual smoke walkthrough | ⏳ user-verified before merge |

## What's next

Phase 2c → Phase 2d (Browser perf — NSOutlineView bridge + virtualized rows for 10k-item directories per strategic doc Phase 1 carry-forward) → Strategic Phase 3 (system integration depth — Quick Look provider, Spotlight, Shortcuts, Services menu, Share Sheet, menubar polish, notifications).

`RcloneSection` Version + Restart Daemon rows re-added when `RcloneDaemon` exposes the underlying APIs (likely alongside Phase 3 menubar polish, when daemon lifecycle becomes more user-facing).
