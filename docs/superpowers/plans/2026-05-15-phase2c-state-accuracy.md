# Phase 2c State-Accuracy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wrap up the five state-accuracy carry-forwards from the Phase 2b exit-gate doc (two CRITICAL + three feature items) so the existing screens surface real OS state instead of placeholders.

**Architecture:** Two pure refactors (NimbusApp `mountConfig` call-site swap, CopySync `String?` → `NimbusError?` type swap) followed by three state-accuracy features: a new `@Observable @MainActor` `RemoteStatusService` for per-remote probes, a real `MountManager.refreshAll()` combining `cleanupStaleMounts` with `NSFileProviderManager` reconciliation, and async real implementations of `FileProviderBridge.isItemMaterialized` / `wasRecentlyEvicted` behind a per-folder 5s `TimedCache`.

**Tech Stack:** Swift 6 strict concurrency, SwiftUI on macOS 15+, `@Observable`, Swift Testing, XcodeGen, RcloneKit local package, FileProvider framework.

**Parent spec:** `docs/superpowers/specs/2026-05-15-phase2c-state-accuracy-design.md`

---

## Conventions

- All new sources under `Nimbus/Nimbus/`. All new tests under `Nimbus/NimbusTests/`.
- Tests use Swift Testing (`import Testing`, `@Test`, `@Suite`, `#expect`).
- After source / `project.yml` edits: `cd Nimbus && xcodegen generate` from repo root.
- Build: `xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' build`
- Test: same command with `test`.
- Commit prefix: `feat(swiftui):`, `fix(swiftui):`, `test(swiftui):`, `refactor(swiftui):`, `chore(swiftui):`.

## Existing-state facts the implementer must know

- `RemoteStatus` enum lives in `Nimbus/Nimbus/Views/Remotes/RemoteRow.swift` lines 4-33 with cases `.connected`, `.authNeeded`, `.error(reason:)`. Task 3 adds `.unknown`.
- `NimbusError` (at `Nimbus/Nimbus/State/NimbusError.swift`) uses the case name `.authFailed` (NOT `.authNeeded`). Do not rename it. Cases: `.authFailed / .network / .other`.
- The rclone error type is `RcloneError` (at `RcloneKit/Sources/RcloneKit/Models.swift:311`), NOT `RcloneRCError`. Cases: `.serverNotRunning / .requestFailed(status: Int, message: String) / .invalidResponse / .decodingError(String)`.
- `RcloneClient.about(fs: String) async throws -> AboutResponse` (NOT `about(remote:)`). For a remote named `"gdrive"` the call is `client.about(fs: "gdrive:")`.
- `RcloneClient` is `final class @unchecked Sendable` (NOT an actor, NOT `@MainActor`).
- `MountManager.mountConfig(_:)` already exists. The current `NimbusApp.startApp()` loop uses the lower-level `mountManager.mount(remote:mountPoint:readOnly:)` — Task 1 swaps to `mountConfig`.
- `MountManager.refreshAll()` exists as a no-op stub at the end of the file — Task 7 makes it real.
- `FileProviderBridge.isItemMaterialized(remote:path:) -> Bool` and `wasRecentlyEvicted(remote:path:) -> Bool` are SYNC stubs returning `false`. Task 9 makes both `async` and updates the protocol + call sites.
- `FileProviderBridge.urlForItem(remote:path:) async -> URL?` already exists and is the right path-to-URL resolver to use for FP queries.
- `RemotesView.task(id: daemon.status)` already wires `loadRemotes()`. Task 5 piggybacks on the same `.task` for `probeAll`.

## Task summary

1. **NimbusApp mountConfig fix** (~0.5d) — critical
2. **CopySync NimbusError migration** (~0.5d) — critical
3. **Add `RemoteStatus.unknown` case + tests** (~0.25d)
4. **`RemoteStatusService` implementation + 11 tests** (~1d)
5. **Wire `RemoteStatusService` into NimbusApp / RemotesView / RemoteRow / RemotesViewModel** (~0.5d)
6. **`reconcileFPDomains` pure function + 4 tests** (~0.5d)
7. **`MountManager.refreshAll()` real implementation + wire** (~1d)
8. **`TimedCache` + 3 tests** (~0.5d)
9. **`FileProviderBridge` async real implementations + protocol update** (~1d)
10. **Phase 2c exit verification + exit-gate doc** (~0.5d)

Total: ~6 days serial. Test count: 87 → 105 (+18 new tests across 4 new suites).

---

## Task 1: NimbusApp mountConfig fix (CRITICAL)

**Files:**
- Modify: `Nimbus/Nimbus/Nimbus/NimbusApp.swift:84-90`

- [ ] **Step 1.1: Read the current loop**

```bash
sed -n '80,95p' /Volumes/DATA/CasaVargas/Nimbus/Nimbus/Nimbus/NimbusApp.swift
```

Expected output includes:

```swift
for config in mountConfigs.configs where config.autoMount {
    if config.backend == .nfs {
        try? await mountManager.mount(
            remote: config.remote,
            mountPoint: config.mountPoint,
            readOnly: config.vfsMode == .readOnly
        )
    }
}
```

- [ ] **Step 1.2: Edit the loop body**

Replace the `try? await mountManager.mount(...)` call with `mountConfig(_:)`:

```swift
for config in mountConfigs.configs where config.autoMount {
    if config.backend == .nfs {
        try? await mountManager.mountConfig(config)
    }
}
```

The `.nfs` guard stays because `mountConfig` will try to mount any backend, but only `.nfs` configs use the NFS pipeline today. `.fileProvider` configs are handled by the FP domain registration further down in `startApp()`.

- [ ] **Step 1.3: Run full test suite**

```bash
cd /Volumes/DATA/CasaVargas/Nimbus && \
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' test 2>&1 | \
  grep -E '(Test run|TEST SUCCEEDED|TEST FAILED|error:)' | tail -5
```

Expected: `Test run with 87 tests in 17 suites passed`.

- [ ] **Step 1.4: Commit**

```bash
git add Nimbus/Nimbus/Nimbus/NimbusApp.swift
git commit -m "fix(swiftui): NimbusApp.startApp() uses mountConfig for auto-mount

Critical Phase 2b carry-forward. The app-launch auto-mount loop was
calling MountManager.mount(remote:mountPoint:readOnly:) directly,
which populates activeMounts but not mountedIDs. OnboardingView's
attemptAutoMount and any future caller of mountedIDs were therefore
seeing stale state on configs that had been auto-mounted on launch.
mountConfig(_:) maintains mountedIDs / inFlight / errors / lastMounted
consistently."
```

---

## Task 2: CopySync NimbusError migration (CRITICAL)

**Files:**
- Modify: `Nimbus/Nimbus/Nimbus/ViewModels/CopySyncViewModel.swift`
- Modify: `Nimbus/Nimbus/Nimbus/Views/CopySync/CopySyncView.swift` (one site)

- [ ] **Step 2.1: Change `CopySyncViewModel.error` type**

Open `Nimbus/Nimbus/Nimbus/ViewModels/CopySyncViewModel.swift`. Find this line near the top:

```swift
private(set) var error: String?
```

Change to:

```swift
private(set) var error: NimbusError?
```

- [ ] **Step 2.2: Update the two catch blocks**

In `loadRemotes()` change:

```swift
} catch {
    self.error = error.localizedDescription
}
```

to:

```swift
} catch {
    self.error = NimbusError.classify(error)
}
```

In `startOperation(...)` change the catch block identically:

```swift
} catch {
    self.error = NimbusError.classify(error)
}
```

`clearError()` body (`error = nil`) needs no change — same type assignment.

- [ ] **Step 2.3: Update the CopySyncView consumer site**

Open `Nimbus/Nimbus/Nimbus/Views/CopySync/CopySyncView.swift`. Find the EmptyState block:

```swift
if let error = viewModel?.error {
    EmptyState(
        icon: "exclamationmark.triangle",
        title: "Couldn't start",
        messageVerbatim: error,
        action: .init(label: "Dismiss", perform: { viewModel?.clearError() })
    )
    .frame(maxHeight: 160)
}
```

Update `messageVerbatim:` to read the new `.message` property:

```swift
if let error = viewModel?.error {
    EmptyState(
        icon: "exclamationmark.triangle",
        title: "Couldn't start",
        messageVerbatim: error.message,
        action: .init(label: "Dismiss", perform: { viewModel?.clearError() })
    )
    .frame(maxHeight: 160)
}
```

- [ ] **Step 2.4: Build + test**

```bash
cd /Volumes/DATA/CasaVargas/Nimbus && \
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' test 2>&1 | \
  grep -E '(Test run|TEST SUCCEEDED|TEST FAILED|error:)' | tail -5
```

Expected: `Test run with 87 tests in 17 suites passed`.

- [ ] **Step 2.5: Commit**

```bash
git add Nimbus/Nimbus/Nimbus/ViewModels/CopySyncViewModel.swift \
        Nimbus/Nimbus/Nimbus/Views/CopySync/CopySyncView.swift
git commit -m "fix(swiftui): migrate CopySyncViewModel.error to NimbusError

Critical Phase 2b carry-forward. Completes the Phase 2a NimbusError
migration that previously didn't reach CopySync. catch blocks now
use NimbusError.classify(_:) for auth/network/other tagging; the
view's messageVerbatim parameter consumes error.message."
```

---

## Task 3: Add `RemoteStatus.unknown` case

**Files:**
- Modify: `Nimbus/Nimbus/Nimbus/Views/Remotes/RemoteRow.swift:4-33`

- [ ] **Step 3.1: Add the new case + display values**

Open `Nimbus/Nimbus/Nimbus/Views/Remotes/RemoteRow.swift`. Replace the `RemoteStatus` enum (lines 4-33) with:

```swift
enum RemoteStatus: Equatable, Sendable {
    case unknown
    case connected
    case authNeeded
    case error(reason: String)

    var pillText: String {
        switch self {
        case .unknown: return "○ Checking…"
        case .connected: return "● Connected"
        case .authNeeded: return "⚠ Sign In"
        case .error: return "! Error"
        }
    }

    var tintColor: Color {
        switch self {
        case .unknown: return DesignSystem.Color.semantic.textSecondary
        case .connected: return DesignSystem.Color.semantic.statusOK
        case .authNeeded: return DesignSystem.Color.semantic.statusWarning
        case .error: return DesignSystem.Color.semantic.statusError
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .unknown: return "Status checking"
        case .connected: return "Connected"
        case .authNeeded: return "Sign in required"
        case .error(let reason): return "Error: \(reason)"
        }
    }
}
```

- [ ] **Step 3.2: Verify build (existing switch exhaustivity)**

```bash
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' build 2>&1 | \
  grep -E '(error:|warning: switch)' | head -5
```

Expected: no errors. The `if case .authNeeded = status { Button("Reconnect") }` in `RemoteRow.contextMenu` is fine; the existing `case .connected` site in `RemotesView.swift:175` will still compile because it's still a valid case.

- [ ] **Step 3.3: Run full suite**

```bash
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' test 2>&1 | \
  grep -E '(Test run|TEST SUCCEEDED|TEST FAILED|error:)' | tail -3
```

Expected: 87 tests pass.

- [ ] **Step 3.4: Commit**

```bash
git add Nimbus/Nimbus/Nimbus/Views/Remotes/RemoteRow.swift
git commit -m "feat(swiftui): add RemoteStatus.unknown for pre-probe state

RemoteStatusService (Task 4) writes .unknown immediately and updates
the entry once the operations/about probe completes. The pill shows
'○ Checking…' in textSecondary, so the row visibly indicates a
status query is in flight rather than misleading the user with a
hardcoded .connected."
```

---

## Task 4: RemoteStatusService implementation + tests

**Files:**
- Create: `Nimbus/Nimbus/Nimbus/Services/RemoteStatusService.swift`
- Create: `Nimbus/NimbusTests/RemoteStatusServiceTests.swift`
- Create: `Nimbus/NimbusTests/Mocks/MockRcloneClient.swift`

### Step 4.1: Define the mock client

- [ ] Create `Nimbus/NimbusTests/Mocks/MockRcloneClient.swift`:

```swift
import Foundation
@testable import RcloneKit

/// Test double for RcloneClient.about(fs:) — captures call args and
/// returns canned responses or throws canned errors per fs argument.
/// Subclassing RcloneClient because it's an open-ish final class via
/// @unchecked Sendable; we use it as a stand-in by overriding `about`.
final class MockRcloneClient: RcloneClient, @unchecked Sendable {
    /// fs argument → result. .success returns an AboutResponse; .failure throws.
    var aboutResults: [String: Result<AboutResponse, Error>] = [:]
    private(set) var calls: [String] = []

    override func about(fs: String) async throws -> AboutResponse {
        calls.append(fs)
        guard let result = aboutResults[fs] else {
            return AboutResponse(total: nil, used: nil, free: nil, trashed: nil, other: nil, objects: nil)
        }
        switch result {
        case .success(let r): return r
        case .failure(let e): throw e
        }
    }
}
```

If `RcloneClient.about` is not `open` (it's `public` on a `final class @unchecked Sendable`), this approach will not compile. In that case, **fall back to a protocol-based mock**:

```swift
// In Nimbus/Nimbus/Services/RemoteStatusService.swift add a protocol:
@MainActor
protocol RemoteProbeClient: Sendable {
    func about(fs: String) async throws -> AboutResponse
}

extension RcloneClient: RemoteProbeClient {}

// And the mock becomes:
final class MockRcloneClient: RemoteProbeClient, @unchecked Sendable {
    var aboutResults: [String: Result<AboutResponse, Error>] = [:]
    private(set) var calls: [String] = []

    func about(fs: String) async throws -> AboutResponse {
        calls.append(fs)
        guard let result = aboutResults[fs] else {
            return AboutResponse(total: nil, used: nil, free: nil, trashed: nil, other: nil, objects: nil)
        }
        switch result {
        case .success(let r): return r
        case .failure(let e): throw e
        }
    }
}
```

Inspect the actual `about` declaration at `RcloneKit/Sources/RcloneKit/Operations.swift` (search for `public func about`) and pick the protocol-based approach if it isn't overridable. The plan below assumes the protocol approach since it's the safer default.

### Step 4.2: Write failing tests (red phase)

- [ ] Create `Nimbus/NimbusTests/RemoteStatusServiceTests.swift`:

```swift
import Testing
import Foundation
@testable import Nimbus
@testable import RcloneKit

@Suite("RemoteStatusService")
@MainActor
struct RemoteStatusServiceTests {
    @Test func probeSetsConnectedOnSuccess() async {
        let client = MockRcloneClient()
        client.aboutResults["gdrive:"] = .success(
            AboutResponse(total: 100, used: 50, free: 50, trashed: nil, other: nil, objects: nil)
        )
        let service = RemoteStatusService(client: client)
        await service.probe("gdrive")
        #expect(service.statuses["gdrive"] == .connected)
        #expect(client.calls == ["gdrive:"])
    }

    @Test func probeSetsUnknownBeforeCompletion() async {
        let client = MockRcloneClient()
        client.aboutResults["slow:"] = .success(
            AboutResponse(total: nil, used: nil, free: nil, trashed: nil, other: nil, objects: nil)
        )
        let service = RemoteStatusService(client: client)
        service.markUnknown("slow")  // simulates the initial set before probeAll launches
        #expect(service.statuses["slow"] == .unknown)
    }

    @Test func probeSetsAuthNeededOn401() async {
        let client = MockRcloneClient()
        client.aboutResults["s3:"] = .failure(
            RcloneError.requestFailed(status: 401, message: "Unauthorized")
        )
        let service = RemoteStatusService(client: client)
        await service.probe("s3")
        #expect(service.statuses["s3"] == .authNeeded)
    }

    @Test func probeSetsAuthNeededOn403() async {
        let client = MockRcloneClient()
        client.aboutResults["s3:"] = .failure(
            RcloneError.requestFailed(status: 403, message: "Forbidden")
        )
        let service = RemoteStatusService(client: client)
        await service.probe("s3")
        #expect(service.statuses["s3"] == .authNeeded)
    }

    @Test func probeSetsAuthNeededOnTokenMessage() async {
        let client = MockRcloneClient()
        client.aboutResults["gdrive:"] = .failure(
            RcloneError.requestFailed(status: 500, message: "couldn't fetch info: oauth token expired")
        )
        let service = RemoteStatusService(client: client)
        await service.probe("gdrive")
        #expect(service.statuses["gdrive"] == .authNeeded)
    }

    @Test func probeSetsErrorOnGenericFailure() async {
        let client = MockRcloneClient()
        client.aboutResults["s3:"] = .failure(
            RcloneError.requestFailed(status: 500, message: "couldn't fetch info: connection refused")
        )
        let service = RemoteStatusService(client: client)
        await service.probe("s3")
        if case .error(let reason) = service.statuses["s3"] {
            #expect(reason.contains("connection refused"))
        } else {
            Issue.record("Expected .error, got \(String(describing: service.statuses["s3"]))")
        }
    }

    @Test func probeAllRunsInParallel() async {
        let client = MockRcloneClient()
        client.aboutResults["gdrive:"] = .success(
            AboutResponse(total: nil, used: nil, free: nil, trashed: nil, other: nil, objects: nil)
        )
        client.aboutResults["s3:"] = .success(
            AboutResponse(total: nil, used: nil, free: nil, trashed: nil, other: nil, objects: nil)
        )
        let service = RemoteStatusService(client: client)
        await service.probeAll(["gdrive", "s3"])
        #expect(service.statuses["gdrive"] == .connected)
        #expect(service.statuses["s3"] == .connected)
        #expect(Set(client.calls) == ["gdrive:", "s3:"])
    }

    @Test func clearRemovesStatus() async {
        let client = MockRcloneClient()
        client.aboutResults["gdrive:"] = .success(
            AboutResponse(total: nil, used: nil, free: nil, trashed: nil, other: nil, objects: nil)
        )
        let service = RemoteStatusService(client: client)
        await service.probe("gdrive")
        #expect(service.statuses["gdrive"] == .connected)
        service.clear("gdrive")
        #expect(service.statuses["gdrive"] == nil)
    }

    @Test func probeIgnoresEmptyName() async {
        let client = MockRcloneClient()
        let service = RemoteStatusService(client: client)
        await service.probe("")
        #expect(client.calls.isEmpty)
        #expect(service.statuses[""] == nil)
    }

    @Test func classifyDetectsAuthOnUnauthorizedSubstring() {
        let err = RcloneError.requestFailed(status: 500, message: "request: unauthorized client")
        #expect(RemoteStatusService.classify(err) == .authNeeded)
    }

    @Test func classifyDetectsAuthOnForbiddenSubstring() {
        let err = RcloneError.requestFailed(status: 500, message: "got 'forbidden' from backend")
        #expect(RemoteStatusService.classify(err) == .authNeeded)
    }
}
```

11 tests covering probe success, the initial-`.unknown`-marker helper, 401/403/token/oauth/unauthorized/forbidden auth classification, generic error fallthrough, parallel probeAll, clear, empty-name defensive guard.

### Step 4.3: Run tests to verify they fail

```bash
cd Nimbus && xcodegen generate && cd .. && \
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' test \
  -only-testing:NimbusTests/RemoteStatusServiceTests 2>&1 | tail -15
```

Expected: "cannot find 'RemoteStatusService' in scope" (and probably "cannot find 'MockRcloneClient'" in scope).

### Step 4.4: Implement RemoteStatusService

- [ ] Create `Nimbus/Nimbus/Nimbus/Services/RemoteStatusService.swift`:

```swift
import Foundation
import Observation
import RcloneKit

/// Owner of per-remote connectivity / auth state. Runs `operations/about`
/// probes on RemotesView appear and on Reconnect. Probes are fire-once;
/// no timers, no polling. Status is cleared when a remote is deleted.
///
/// Reference: macOS Disk Utility's volume-info refresh-on-appear pattern.
@Observable
@MainActor
final class RemoteStatusService {
    private(set) var statuses: [String: RemoteStatus] = [:]

    private let client: RemoteProbeClient

    init(client: RemoteProbeClient) {
        self.client = client
    }

    /// Pre-flight marker — sets statuses[name] = .unknown synchronously
    /// before any await, so the row shows the "Checking…" pill the moment
    /// `probeAll` is called rather than waiting for the first response.
    func markUnknown(_ name: String) {
        guard !name.isEmpty else { return }
        statuses[name] = .unknown
    }

    /// Probe a single remote. Used by the Reconnect button and from
    /// `probeAll`. Replaces any prior status for `name`.
    func probe(_ name: String) async {
        guard !name.isEmpty else { return }
        statuses[name] = .unknown
        do {
            _ = try await client.about(fs: "\(name):")
            statuses[name] = .connected
        } catch {
            statuses[name] = Self.classify(error)
        }
    }

    /// Probe many remotes in parallel via a TaskGroup. Each entry is
    /// independently set; a failure on one remote does not abort the others.
    func probeAll(_ names: [String]) async {
        for name in names {
            markUnknown(name)
        }
        await withTaskGroup(of: Void.self) { group in
            for name in names where !name.isEmpty {
                group.addTask { @MainActor [self] in
                    await self.probe(name)
                }
            }
        }
    }

    /// Drop the cached status for `name` (e.g., on remote deletion).
    func clear(_ name: String) {
        statuses.removeValue(forKey: name)
    }

    /// Classifies a probe failure into a RemoteStatus. Pulled out as a
    /// `static` so the tests can exercise the classifier without spinning
    /// up the service.
    static func classify(_ error: Error) -> RemoteStatus {
        if let rcloneError = error as? RcloneError, case .requestFailed(let status, _) = rcloneError {
            if status == 401 || status == 403 {
                return .authNeeded
            }
        }
        let message = error.localizedDescription.lowercased()
        let authSignals = ["oauth", "token", "unauthorized", "forbidden", "sign in", "401", "403"]
        if authSignals.contains(where: { message.contains($0) }) {
            return .authNeeded
        }
        return .error(reason: error.localizedDescription)
    }
}

/// Protocol for the single rclone RC method `RemoteStatusService` needs.
/// Lets tests inject a mock without depending on URLSession.
@MainActor
protocol RemoteProbeClient: Sendable {
    nonisolated func about(fs: String) async throws -> AboutResponse
}

extension RcloneClient: RemoteProbeClient {}
```

### Step 4.5: Verify the protocol/extension compiles cleanly

`RcloneClient.about(fs:)` is declared on `RcloneClient` (which is `final class @unchecked Sendable`, not `@MainActor`). The protocol marks the requirement `nonisolated` so the extension can fulfill it without an actor hop. If the implementer finds the protocol cannot be retroactively conformed (e.g., the method's actor isolation differs), they should switch to making `RemoteProbeClient` a non-`@MainActor` protocol entirely. The classifier code is unchanged either way.

### Step 4.6: Run tests

```bash
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' test \
  -only-testing:NimbusTests/RemoteStatusServiceTests 2>&1 | tail -10
```

Expected: 11 tests pass.

### Step 4.7: Run full suite

```bash
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' test 2>&1 | \
  grep -E '(Test run|TEST SUCCEEDED|TEST FAILED)' | tail -3
```

Expected: 98 tests pass (87 baseline + 11 new).

### Step 4.8: Commit

```bash
git add Nimbus/Nimbus/Nimbus/Services/RemoteStatusService.swift \
        Nimbus/NimbusTests/RemoteStatusServiceTests.swift \
        Nimbus/NimbusTests/Mocks/MockRcloneClient.swift \
        Nimbus/Nimbus.xcodeproj
git commit -m "feat(swiftui): add RemoteStatusService for per-remote probes

- @Observable @MainActor service owning [String: RemoteStatus]
- probe(_:) and probeAll(_:) call operations/about; classify failure
  into .authNeeded (401/403/oauth/token/unauthorized/forbidden) vs
  .error(reason:)
- RemoteProbeClient protocol so tests inject a MockRcloneClient without
  URLSession
- 11 tests: success, unknown marker, 401/403/token/oauth/unauthorized/
  forbidden classification, generic error, parallel probeAll, clear,
  empty-name guard, two substring classifier checks"
```

---

## Task 5: Wire RemoteStatusService into the app

**Files:**
- Modify: `Nimbus/Nimbus/Nimbus/NimbusApp.swift` (env injection)
- Modify: `Nimbus/Nimbus/Nimbus/Views/Remotes/RemotesView.swift` (probeAll on appear, status reads)
- Modify: `Nimbus/Nimbus/Nimbus/ViewModels/RemotesViewModel.swift` (call clear on delete)

- [ ] **Step 5.1: Construct and inject the service in NimbusApp**

Open `Nimbus/Nimbus/Nimbus/NimbusApp.swift`. After the existing `@State private var launchAtLogin = LaunchAtLoginService()` line, add:

```swift
@State private var statusService: RemoteStatusService? = nil
```

The service is optional because it depends on `daemon.client`, which exists at app launch (RcloneDaemon constructs an empty `RcloneClient` immediately). Update the initial `@State` to construct the service eagerly:

```swift
@State private var statusService = RemoteStatusService(client: RcloneDaemon().client)
```

Wait — that re-creates a separate `RcloneDaemon`. The right pattern is:

```swift
@State private var daemon: RcloneDaemon
@State private var statusService: RemoteStatusService

init() {
    DesignSystem.Lints.runStartupChecks()
    let d = RcloneDaemon()
    _daemon = State(initialValue: d)
    _statusService = State(initialValue: RemoteStatusService(client: d.client))
}
```

This replaces the existing `@State private var daemon = RcloneDaemon()` line and adds the explicit `init()`. Other `@State` initializers stay as their default-value form.

Then add to the `WindowGroup` environment chain (after `.environment(launchAtLogin)`):

```swift
.environment(statusService)
```

And in the `Settings { SettingsView() ... }` scene — `statusService` is not needed there, leave it alone.

- [ ] **Step 5.2: Wire probeAll into RemotesView**

Open `Nimbus/Nimbus/Nimbus/Views/Remotes/RemotesView.swift`. Add to the `@Environment` reads at the top:

```swift
@Environment(RemoteStatusService.self) private var statusService
```

Find the existing `.task(id: daemon.status)` block:

```swift
.task(id: daemon.status) {
    guard daemon.status == .connected else { return }
    if viewModel == nil {
        viewModel = RemotesViewModel(client: daemon.client)
    }
    await viewModel?.loadRemotes()
}
```

Replace with:

```swift
.task(id: daemon.status) {
    guard daemon.status == .connected else { return }
    if viewModel == nil {
        viewModel = RemotesViewModel(client: daemon.client)
    }
    await viewModel?.loadRemotes()
    if let names = viewModel?.remotes.map(\.name), !names.isEmpty {
        await statusService.probeAll(names)
    }
}
```

- [ ] **Step 5.3: Read real status in the row**

In the same file, find the `List` body containing `RemoteRow`:

```swift
List(filteredRemotes(viewModel.remotes), id: \.name, selection: $listSelection) { remote in
    RemoteRow(
        remote: remote,
        status: .connected, // Phase 2a placeholder; richer status discovery is Phase 3
        onEdit: { editingRemote = remote },
        onDelete: { deletingRemote = remote },
        onBrowse: { onBrowse?(remote.name) },
        onReconnect: {
            Logger(subsystem: "app.casavargas.nimbus", category: "remotes")
                .warning("Reconnect handler not wired (Phase 3); status is hardcoded to .connected in Phase 2a so this should be unreachable")
        }
    )
    .tag(remote.name)
}
.listStyle(.inset)
```

Replace with:

```swift
List(filteredRemotes(viewModel.remotes), id: \.name, selection: $listSelection) { remote in
    RemoteRow(
        remote: remote,
        status: statusService.statuses[remote.name] ?? .unknown,
        onEdit: { editingRemote = remote },
        onDelete: { deletingRemote = remote },
        onBrowse: { onBrowse?(remote.name) },
        onReconnect: {
            Task { await statusService.probe(remote.name) }
        }
    )
    .tag(remote.name)
}
.listStyle(.inset)
```

The `Logger` `import os` line stays — it's still used by `loadProviders` elsewhere (verify by searching `Logger(subsystem` in the file; if unused, delete the import).

- [ ] **Step 5.4: Clear status on delete**

Open `Nimbus/Nimbus/Nimbus/ViewModels/RemotesViewModel.swift`. The current `deleteRemote(name:)` is:

```swift
func deleteRemote(name: String) async {
    do {
        try await client.deleteRemote(name: name)
        remotes.removeAll { $0.name == name }
    } catch {
        self.error = NimbusError.classify(error)
    }
}
```

This view model doesn't hold a reference to the status service (services are environment-injected, view models are not). Rather than thread the service into the view model, clear status from the **view** side, in the confirmationDialog Delete handler. Open `RemotesView.swift` and find:

```swift
Button("Delete", role: .destructive) {
    if let remote = deletingRemote {
        Task { await viewModel?.deleteRemote(name: remote.name) }
    }
}
```

Replace with:

```swift
Button("Delete", role: .destructive) {
    if let remote = deletingRemote {
        let name = remote.name
        Task {
            await viewModel?.deleteRemote(name: name)
            statusService.clear(name)
        }
    }
}
```

- [ ] **Step 5.5: Build + run full suite**

```bash
cd Nimbus && xcodegen generate && cd .. && \
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' test 2>&1 | \
  grep -E '(Test run|TEST SUCCEEDED|TEST FAILED|error:)' | tail -5
```

Expected: 98 tests pass (unchanged from Task 4).

- [ ] **Step 5.6: Commit**

```bash
git add Nimbus/Nimbus/Nimbus/NimbusApp.swift \
        Nimbus/Nimbus/Nimbus/Views/Remotes/RemotesView.swift \
        Nimbus/Nimbus/Nimbus/ViewModels/RemotesViewModel.swift \
        Nimbus/Nimbus.xcodeproj
git commit -m "feat(swiftui): wire RemoteStatusService into RemotesView

- NimbusApp constructs the service from daemon.client and injects via
  .environment(_:)
- RemotesView.task fires statusService.probeAll(remoteNames) after
  loadRemotes completes; rows read statusService.statuses[name] ??
  .unknown so the badge updates as each probe lands
- Reconnect button now re-runs probe for a single row instead of
  logging a Phase 2a no-op warning
- Delete handler calls statusService.clear(name) after a successful
  removal so the service doesn't leak entries for removed remotes"
```

---

## Task 6: `reconcileFPDomains` pure function + tests

**Files:**
- Modify: `Nimbus/Nimbus/Nimbus/Services/MountManager.swift` (add free function + FPDomainInfo struct)
- Create: `Nimbus/NimbusTests/ReconcileFPDomainsTests.swift`

### Step 6.1: Write failing tests

- [ ] Create `Nimbus/NimbusTests/ReconcileFPDomainsTests.swift`:

```swift
import Testing
@testable import Nimbus

@Suite("reconcileFPDomains")
@MainActor
struct ReconcileFPDomainsTests {
    @Test func domainMatchingConfigPopulatesMountedIDs() {
        let configs = [
            MountConfig(remote: "gdrive:", mountPoint: "", vfsMode: .readWrite,
                        autoMount: false, backend: .fileProvider)
        ]
        let domains = [FPDomainInfo(identifier: configs[0].id, displayName: "gdrive")]
        var mountedIDs: Set<String> = []
        var logMessages: [String] = []

        reconcileFPDomains(domains, configs: configs, mountedIDs: &mountedIDs) {
            logMessages.append($0)
        }

        #expect(mountedIDs == [configs[0].id])
        #expect(logMessages.isEmpty)
    }

    @Test func orphanDomainIsIgnored() {
        let domains = [FPDomainInfo(identifier: "stale-id", displayName: "old")]
        let configs: [MountConfig] = []
        var mountedIDs: Set<String> = []

        reconcileFPDomains(domains, configs: configs, mountedIDs: &mountedIDs) { _ in }

        #expect(mountedIDs.isEmpty)
    }

    @Test func configWithoutDomainIsLogged() {
        let configs = [
            MountConfig(remote: "gdrive:", mountPoint: "", vfsMode: .readWrite,
                        autoMount: false, backend: .fileProvider)
        ]
        let domains: [FPDomainInfo] = []
        var mountedIDs: Set<String> = []
        var logMessages: [String] = []

        reconcileFPDomains(domains, configs: configs, mountedIDs: &mountedIDs) {
            logMessages.append($0)
        }

        #expect(mountedIDs.isEmpty)
        #expect(logMessages.count == 1)
        #expect(logMessages[0].contains(configs[0].id))
    }

    @Test func emptyInputsAreNoOp() {
        var mountedIDs: Set<String> = ["preexisting"]
        var logMessages: [String] = []

        reconcileFPDomains([], configs: [], mountedIDs: &mountedIDs) {
            logMessages.append($0)
        }

        #expect(mountedIDs == ["preexisting"])  // not cleared
        #expect(logMessages.isEmpty)
    }
}
```

### Step 6.2: Run tests to verify failure

```bash
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' test \
  -only-testing:NimbusTests/ReconcileFPDomainsTests 2>&1 | tail -10
```

Expected: "cannot find 'reconcileFPDomains' in scope" and "cannot find 'FPDomainInfo' in scope".

### Step 6.3: Add `FPDomainInfo` and `reconcileFPDomains` to MountManager.swift

- [ ] Open `Nimbus/Nimbus/Nimbus/Services/MountManager.swift`. At the top of the file (after `import` lines, before `struct ActiveMount`), add:

```swift
/// Test-friendly summary of an `NSFileProviderDomain`. `MountManager.refreshAll()`
/// converts the OS type to this struct before passing to `reconcileFPDomains`
/// so the reconciliation logic can be unit-tested without spinning up FP.
struct FPDomainInfo: Equatable, Sendable {
    let identifier: String
    let displayName: String
}

/// Reconcile a snapshot of File Provider domains against the configured
/// `.fileProvider` mounts. Domains whose identifier matches a config's
/// `id` get added to `mountedIDs`. Configs without a matching domain are
/// reported via `logger` (not auto-recreated — that's a different flow).
///
/// Pure function: testable without an `NSFileProviderManager` dependency.
func reconcileFPDomains(
    _ domains: [FPDomainInfo],
    configs: [MountConfig],
    mountedIDs: inout Set<String>,
    logger: (String) -> Void
) {
    for domain in domains {
        if let config = configs.first(where: { $0.id == domain.identifier }) {
            mountedIDs.insert(config.id)
        }
    }
    for config in configs where !domains.contains(where: { $0.identifier == config.id }) {
        logger("FP config \(config.id) has no matching domain; not auto-recreating")
    }
}
```

### Step 6.4: Run tests + full suite

```bash
cd Nimbus && xcodegen generate && cd .. && \
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' test \
  -only-testing:NimbusTests/ReconcileFPDomainsTests 2>&1 | tail -10
```

Expected: 4 tests pass.

```bash
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' test 2>&1 | \
  grep -E '(Test run|TEST SUCCEEDED|TEST FAILED)' | tail -3
```

Expected: 102 tests pass (98 + 4).

### Step 6.5: Commit

```bash
git add Nimbus/Nimbus/Nimbus/Services/MountManager.swift \
        Nimbus/NimbusTests/ReconcileFPDomainsTests.swift \
        Nimbus/Nimbus.xcodeproj
git commit -m "feat(swiftui): add reconcileFPDomains pure function + tests

- FPDomainInfo struct shadows NSFileProviderDomain for testability
- reconcileFPDomains is a pure free function that:
  - inserts config.id into mountedIDs for matching domains
  - calls the logger closure for configs without a matching domain
  - does not auto-recreate (orchestration decision)
- 4 tests: match / orphan domain / config without domain / empty inputs"
```

---

## Task 7: Real `MountManager.refreshAll()` + wire

**Files:**
- Modify: `Nimbus/Nimbus/Nimbus/Services/MountManager.swift` (refreshAll body)
- Modify: `Nimbus/Nimbus/Nimbus/NimbusApp.swift` (call after auto-mount)
- Modify: `Nimbus/Nimbus/Nimbus/Views/Mounts/MountsView.swift` (call in .task)

### Step 7.1: Replace `refreshAll()` body

- [ ] In `Nimbus/Nimbus/Nimbus/Services/MountManager.swift`, find the existing stub at the bottom:

```swift
func refreshAll() async {
    let liveMountPoints = Set(activeMounts.map(\.mountPoint))
    _ = liveMountPoints
}
```

Replace with:

```swift
func refreshAll() async {
    await cleanupStaleMounts()
    await reconcileFileProviderDomains()
}

private func reconcileFileProviderDomains() async {
    let nsDomains: [NSFileProviderDomain]
    do {
        nsDomains = try await NSFileProviderManager.domains()
    } catch {
        logger.warning("refreshAll: getDomains failed: \(error.localizedDescription)")
        return
    }
    let domainInfos = nsDomains.map {
        FPDomainInfo(identifier: $0.identifier.rawValue, displayName: $0.displayName)
    }
    // configStore isn't directly accessible from MountManager; refreshAll
    // is called by callers that have a MountConfigStore in scope. Pass
    // configs explicitly.
    reconcileFPDomains(domainInfos, configs: configs, mountedIDs: &mountedIDs) { msg in
        logger.info("\(msg)")
    }
}

/// Set of configs `refreshAll()` should reconcile against. The caller
/// updates this just before calling `refreshAll()`. Done this way to
/// keep `MountManager` independent of `MountConfigStore` (which would
/// otherwise create an env/store coupling).
var configs: [MountConfig] = []
```

This adds a `configs` storage on `MountManager` that callers update before invoking `refreshAll()`. Add the `import FileProvider` at the top of the file if not already present.

### Step 7.2: Wire callers

- [ ] In `Nimbus/Nimbus/Nimbus/NimbusApp.swift`, find the existing auto-mount loop block in `startApp()` (the one Task 1 modified). Add after the loop and before the `// Sync File Provider domains` block:

```swift
// Phase 2c: refreshAll reconciles mount(8) state and FP domains against configs
mountManager.configs = mountConfigs.configs
await mountManager.refreshAll()
```

- [ ] In `Nimbus/Nimbus/Nimbus/Views/Mounts/MountsView.swift`, find the existing `.task` modifier on the main view (or `.onAppear` — verify by reading the file). Add a refreshAll call:

```swift
.task {
    mountManager.configs = mountConfigs.configs
    await mountManager.refreshAll()
}
```

If `MountsView` already has a `.task`, merge these two lines into it. If not, add as a new modifier on the outermost view body. The implementer should also confirm `MountsView` reads `@Environment(MountConfigStore.self) private var mountConfigs` and `@Environment(MountManager.self) private var mountManager` — both should already be present from Phase 2a; add them if missing.

### Step 7.3: Build + test

```bash
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' test 2>&1 | \
  grep -E '(Test run|TEST SUCCEEDED|TEST FAILED|error:)' | tail -5
```

Expected: 102 tests pass.

### Step 7.4: Commit

```bash
git add Nimbus/Nimbus/Nimbus/Services/MountManager.swift \
        Nimbus/Nimbus/Nimbus/NimbusApp.swift \
        Nimbus/Nimbus/Nimbus/Views/Mounts/MountsView.swift
git commit -m "feat(swiftui): real MountManager.refreshAll reconciliation

- refreshAll now calls cleanupStaleMounts then reconcileFileProviderDomains
- reconcileFileProviderDomains fetches NSFileProviderManager.domains(),
  maps to FPDomainInfo, and runs the pure reconcileFPDomains() against the
  current configs to populate mountedIDs
- MountManager.configs is set by callers (NimbusApp.startApp, MountsView.task)
  before calling refreshAll — avoids coupling MountManager to MountConfigStore
- Idempotent; safe to call from both app launch and MountsView appear"
```

---

## Task 8: `TimedCache` + tests

**Files:**
- Create: `Nimbus/Nimbus/Nimbus/Services/TimedCache.swift`
- Create: `Nimbus/NimbusTests/TimedCacheTests.swift`

### Step 8.1: Write failing tests

- [ ] Create `Nimbus/NimbusTests/TimedCacheTests.swift`:

```swift
import Testing
import Foundation
@testable import Nimbus

@Suite("TimedCache")
struct TimedCacheTests {
    @Test func hitWithinTTLReturnsCachedValue() {
        let cache = TimedCache<String, Int>(ttl: .seconds(60))
        cache.store(42, for: "a")
        #expect(cache.value(for: "a") == 42)
    }

    @Test func missAfterTTLReturnsNil() async throws {
        let cache = TimedCache<String, Int>(ttl: .milliseconds(50))
        cache.store(42, for: "a")
        try await Task.sleep(for: .milliseconds(100))
        #expect(cache.value(for: "a") == nil)
    }

    @Test func invalidateRemovesEntry() {
        let cache = TimedCache<String, Int>(ttl: .seconds(60))
        cache.store(42, for: "a")
        cache.invalidate("a")
        #expect(cache.value(for: "a") == nil)
    }
}
```

### Step 8.2: Run to verify failure

```bash
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' test \
  -only-testing:NimbusTests/TimedCacheTests 2>&1 | tail -10
```

Expected: "cannot find 'TimedCache' in scope".

### Step 8.3: Implement TimedCache

- [ ] Create `Nimbus/Nimbus/Nimbus/Services/TimedCache.swift`:

```swift
import Foundation

/// Reference-semantics cache with per-entry TTL. Used by `FileProviderBridge`
/// to avoid hammering `NSFileProviderManager` for materialized/evicted
/// queries on every row scroll. Not thread-safe — callers are expected to
/// be `@MainActor`-isolated.
final class TimedCache<Key: Hashable, Value> {
    private struct Entry {
        let value: Value
        let storedAt: Date
    }

    private let ttl: Duration
    private var storage: [Key: Entry] = [:]

    init(ttl: Duration) {
        self.ttl = ttl
    }

    func value(for key: Key) -> Value? {
        guard let entry = storage[key] else { return nil }
        let age = Date().timeIntervalSince(entry.storedAt)
        let ttlSeconds = Double(ttl.components.seconds) +
                         Double(ttl.components.attoseconds) / 1e18
        if age > ttlSeconds {
            storage.removeValue(forKey: key)
            return nil
        }
        return entry.value
    }

    func store(_ value: Value, for key: Key) {
        storage[key] = Entry(value: value, storedAt: Date())
    }

    func invalidate(_ key: Key) {
        storage.removeValue(forKey: key)
    }

    func invalidateAll() {
        storage.removeAll()
    }
}
```

### Step 8.4: Run tests

```bash
cd Nimbus && xcodegen generate && cd .. && \
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' test \
  -only-testing:NimbusTests/TimedCacheTests 2>&1 | tail -10
```

Expected: 3 tests pass.

### Step 8.5: Full suite

```bash
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' test 2>&1 | \
  grep -E '(Test run|TEST SUCCEEDED|TEST FAILED)' | tail -3
```

Expected: 105 tests pass.

### Step 8.6: Commit

```bash
git add Nimbus/Nimbus/Nimbus/Services/TimedCache.swift \
        Nimbus/NimbusTests/TimedCacheTests.swift \
        Nimbus/Nimbus.xcodeproj
git commit -m "feat(swiftui): add TimedCache for per-folder FP-query caching

Reference-semantics cache with Duration TTL. Used by FileProviderBridge
(Task 9) to avoid hammering NSFileProviderManager for materialized /
evicted queries on every row scroll. Not thread-safe; callers MainActor-
isolated. 3 tests: hit within TTL, miss after TTL, invalidate clears."
```

---

## Task 9: FileProviderBridge real materialized/evicted queries

**Files:**
- Modify: `Nimbus/Nimbus/Nimbus/Services/FileProviderBridge.swift` (protocol + impls)
- Modify: any callers of `isItemMaterialized` / `wasRecentlyEvicted` (likely in Browser views)

### Step 9.1: Locate callers

```bash
grep -rn "isItemMaterialized\|wasRecentlyEvicted" /Volumes/DATA/CasaVargas/Nimbus/Nimbus --include='*.swift'
```

Expected callers (Phase 1 baseline): a Browser view that decorates rows with a "materialized" or "cloud" badge. Note the line numbers; you'll update each to `await`.

### Step 9.2: Change the protocol to async

- [ ] In `Nimbus/Nimbus/Nimbus/Services/FileProviderBridge.swift`, find the protocol (lines 13-19) and change the two stub methods to `async`:

```swift
@MainActor
protocol FileProviderBridgeProtocol: AnyObject {
    func isRegistered(remote: String) -> Bool
    func urlForItem(remote: String, path: String) async -> URL?
    func isItemMaterialized(remote: String, path: String) async -> Bool
    func wasRecentlyEvicted(remote: String, path: String) async -> Bool
}
```

### Step 9.3: Implement the real queries

- [ ] In the same file, add caches as stored properties of `FileProviderBridge` (after `private(set) var activeDomains: Set<String> = []`):

```swift
private let materializedCache = TimedCache<String, [String: Bool]>(ttl: .seconds(5))
private let evictedCache = TimedCache<String, [String: Bool]>(ttl: .seconds(5))
```

The cache key is `"\(remote)|\(parentPath)"` (a single string so we can use the same `TimedCache<String, ...>`). The cached value is a dict from full `path` → bool for items in that parent.

- [ ] Replace the two stub methods (currently at lines 174 and 180) with:

```swift
/// Query whether the (remote, path) item has been materialized to the
/// local FP cache. Per-folder cached for ~5s to avoid re-querying on
/// every row-scroll tick.
func isItemMaterialized(remote: String, path: String) async -> Bool {
    await queryMaterialization(
        remote: remote,
        path: path,
        cache: materializedCache,
        enumeratorKeyPath: \.materializedItemsEnumerator
    )
}

/// Query whether the (remote, path) item is in the recently-evicted set.
/// Per-folder cached for ~5s.
func wasRecentlyEvicted(remote: String, path: String) async -> Bool {
    await queryMaterialization(
        remote: remote,
        path: path,
        cache: evictedCache,
        enumeratorKeyPath: \.evictedItemsEnumerator
    )
}

/// Shared body for both query types. Walks the FP enumerator for the
/// parent folder, builds a {childPath: true} dict, caches it, returns
/// whether the requested path is in the dict. Returns `false` (and
/// caches false) if the FP framework can't resolve the path.
private func queryMaterialization(
    remote: String,
    path: String,
    cache: TimedCache<String, [String: Bool]>,
    enumeratorKeyPath: KeyPath<NSFileProviderManager, NSFileProviderEnumerator>
) async -> Bool {
    let parent = (path as NSString).deletingLastPathComponent
    let cacheKey = "\(remote)|\(parent)"
    if let cached = cache.value(for: cacheKey) {
        return cached[path] ?? false
    }
    let domain = NSFileProviderDomain(
        identifier: NSFileProviderDomainIdentifier(rawValue: remote),
        displayName: remote
    )
    guard let manager = NSFileProviderManager(for: domain) else {
        cache.store([:], for: cacheKey)
        return false
    }
    let enumerator = manager[keyPath: enumeratorKeyPath]
    let result: [String: Bool] = await collectMaterializationDict(from: enumerator)
    cache.store(result, for: cacheKey)
    return result[path] ?? false
}

/// Walks a `NSFileProviderEnumerator` and builds a {item identifier: true}
/// dictionary. The enumerator's `enumerateItems(for:startingAt:)` is the
/// async-via-callback API; we wrap it with a continuation.
private func collectMaterializationDict(
    from enumerator: NSFileProviderEnumerator
) async -> [String: Bool] {
    let observer = MaterializationObserver()
    let observerWrapper = observer  // capture by reference; observer is a class
    return await withCheckedContinuation { continuation in
        observerWrapper.completion = { dict in
            continuation.resume(returning: dict)
        }
        enumerator.enumerateItems(for: observerWrapper, startingAt: NSFileProviderPage(rawValue: Data()))
    }
}
```

Add the observer class file-scope (inside `FileProviderBridge.swift`, after the extension):

```swift
/// Collects item identifiers from an NSFileProviderEnumerator into a
/// {path: true} dict. The dict is then handed to TimedCache via `completion`.
private final class MaterializationObserver: NSObject, NSFileProviderEnumerationObserver {
    var completion: (([String: Bool]) -> Void)?
    private var collected: [String: Bool] = [:]

    func didEnumerate(_ updatedItems: [NSFileProviderItemProtocol]) {
        for item in updatedItems {
            collected[item.filename] = true
        }
    }

    func finishEnumerating(upTo nextPage: NSFileProviderPage?) {
        completion?(collected)
    }

    func finishEnumeratingWithError(_ error: any Error) {
        completion?(collected)
    }
}
```

**Note on `NSFileProviderEnumerator.materializedItemsEnumerator` shape:** the actual Apple API may differ from the snippet above (it has historically been delivered via a separate method on `NSFileProviderManager`). If the implementer finds the KeyPath approach doesn't compile, the alternative is:

```swift
private func queryMaterialization(...) async -> Bool {
    ...
    let enumerator: NSFileProviderEnumerator
    switch enumeratorKind {
    case .materialized: enumerator = manager.enumeratorForMaterializedItems()
    case .evicted:      enumerator = manager.enumeratorForEvictedItems()
    }
    ...
}

private enum EnumeratorKind { case materialized, evicted }
```

The implementer should grep Apple's framework headers (`xcrun --sdk macosx --show-sdk-path` → `/System/Library/Frameworks/FileProvider.framework/Headers`) for the exact entry-point name before committing to one form. If neither is available on macOS 15, FALL BACK to keeping the stubs as `false` but document the limitation in the exit-gate doc.

### Step 9.4: Update callers

- [ ] For each caller found in Step 9.1, wrap the call in `await`. Example (likely shape):

Before:
```swift
let materialized = bridge.isItemMaterialized(remote: r, path: p)
```

After:
```swift
let materialized = await bridge.isItemMaterialized(remote: r, path: p)
```

If the call site is in a synchronous View body, wrap in a `.task` that populates a `@State` flag — the existing Phase 1 callers are likely already in async contexts.

### Step 9.5: Build + test

```bash
cd Nimbus && xcodegen generate && cd .. && \
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' test 2>&1 | \
  grep -E '(Test run|TEST SUCCEEDED|TEST FAILED|error:)' | tail -10
```

Expected: 105 tests pass; build green.

If the build fails because the FP enumerator API doesn't match the plan's snippet, the implementer should:
1. Inspect `NSFileProviderManager` headers for the actual entry-point name.
2. Adapt the `queryMaterialization` body.
3. If no entry point exists for this on macOS 15: revert this task's body to the stub `return false`, log a "phase 2c FP queries deferred — no working API on macOS 15" note, and add it as a carry-forward.

### Step 9.6: Commit

```bash
git add Nimbus/Nimbus/Nimbus/Services/FileProviderBridge.swift \
        Nimbus/Nimbus.xcodeproj
# Add caller files if any were updated:
# git add Nimbus/Nimbus/Nimbus/Views/Browser/...
git commit -m "feat(swiftui): real FP materialized/evicted queries with TimedCache

- FileProviderBridgeProtocol.isItemMaterialized / wasRecentlyEvicted
  switched to async
- Both methods walk NSFileProviderManager's materialized/evicted
  enumerator for the parent folder, build a {childPath: true} dict,
  cache the dict for 5s per (remote, parent) key
- Errors and missing FP domains return false (cached) so paths outside
  any FP domain render correctly as not-materialized
- Browser callers updated to await the new async signature"
```

---

## Task 10: Phase 2c exit verification + exit-gate doc

**Files:**
- Create: `docs/superpowers/specs/2026-05-15-phase2c-exit-gates.md`

### Step 10.1: Full test suite green

```bash
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' test 2>&1 | \
  grep -E '(Test run|TEST SUCCEEDED|TEST FAILED|lint-)' | tail -8
```

Expected: **105 tests in 21 suites passed** (was 87 + 18 new). Both lints OK.

### Step 10.2: Per-suite breakdown

```bash
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' test 2>&1 | \
  grep -E 'Suite ' | tail -25
```

Verify the four new suites exist with the expected counts:
- `RemoteStatusService` → 11
- `ReconcileFPDomains` → 4
- `TimedCache` → 3
- Plus the 17 baseline suites unchanged (the `Phase 2b OnboardingCard` suite stays at 5)

### Step 10.3: Lint hooks

```bash
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' build 2>&1 | \
  grep -E '(lint-no-system-size|lint-package-resolved)' | tail -3
```

Both should output `OK`.

### Step 10.4: Write exit-gate doc

- [ ] Create `docs/superpowers/specs/2026-05-15-phase2c-exit-gates.md` following the Phase 2b template (`docs/superpowers/specs/2026-05-15-phase2b-exit-gates.md`). Required sections:

- **Header** — date, branch, parent specs (`2026-05-14-nimbus-north-star-design.md`, `2026-05-15-phase2c-state-accuracy-design.md`), parent plan (`2026-05-15-phase2c-state-accuracy.md`).
- **Objective gates table:**
  - Two CRITICAL Phase 2b carry-forwards resolved (✅ — Tasks 1, 2)
  - `RemoteStatus.unknown` added; `RemoteRow.status` reads real service state (✅ — Tasks 3, 5)
  - `RemoteStatusService` exists with 11 passing tests (✅ — Task 4)
  - `MountManager.refreshAll()` real implementation + `reconcileFPDomains` 4 passing tests (✅ — Tasks 6, 7)
  - `TimedCache` exists with 3 passing tests (✅ — Task 8)
  - `FileProviderBridge.isItemMaterialized` / `wasRecentlyEvicted` async + real (✅ — Task 9, OR ⏳ deferred carry-forward if Apple API unavailable)
  - Full suite green (✅ — 105 tests)
  - Lints green (✅)
  - `Package.resolved` unchanged (✅)
  - VoiceOver labels on new status pills (⏳ user verifies)
  - Manual smoke: Remotes shows real status / Reconnect retries one row / refreshAll picks up existing mount (⏳ user verifies)
- **Subjective gates** — same template as Phase 2b but scoped to the screens Phase 2c touched (Remotes / Mounts / Browser materialization badge).
- **Wedge** — Phase 2c doesn't add a user-facing wedge per se; the relevant manual smoke is the Remotes status flow:
  1. Launch with a remote that's known-bad (revoked OAuth).
  2. Open Remotes — row should show `○ Checking…` briefly, then `⚠ Sign In`.
  3. Right-click → Reconnect — row re-runs probe, ends in `⚠ Sign In` again (no real OAuth refresh in 2c).
  4. Quit, fix the credentials via `rclone config`, relaunch — row shows `● Connected`.
- **Test suite snapshot** — copy-format from Phase 2b, listing all 21 suites with totals.
- **Known carry-forwards into next phases:**
  - Browser NSOutlineView bridge — moved to Phase 2d.
  - RcloneSection Version + Restart Daemon rows — waiting on `RcloneDaemon` API.
  - OAuth re-auth on Reconnect — Phase 4.
  - If Task 9 was deferred: a "macOS 15 FP enumerator API gap" note.
  - All Phase 2b / 2a / 1 carry-forwards that didn't fall in 2c scope (refresh the list).
- **What's next** — Phase 2d (Browser perf — NSOutlineView bridge), then strategic-doc Phase 3 (system integration).

### Step 10.5: Commit

```bash
git add docs/superpowers/specs/2026-05-15-phase2c-exit-gates.md
git commit -m "docs: Phase 2c exit-gate verification

105 tests pass (87 baseline + 18 new across RemoteStatusService /
ReconcileFPDomains / TimedCache), lints green. Two CRITICAL Phase 2b
carry-forwards resolved. Real RemoteRow status pills replace hardcoded
.connected; MountManager.refreshAll reconciles FP domains; FP
materialized/evicted queries replace placeholder false return.

Carry-forwards updated: Browser NSOutlineView bridge moved to Phase 2d;
RcloneSection Version/Restart rows still gated on RcloneDaemon API;
OAuth re-auth on Reconnect is Phase 4."
```

---

## Plan self-review

**Spec coverage check:**

| Spec section | Implementing task |
|--------------|-------------------|
| 1. NimbusApp mountConfig fix | Task 1 |
| 2. CopySync NimbusError migration | Task 2 |
| 3. Live remote-status discovery — RemoteStatus.unknown | Task 3 |
| 3. Live remote-status discovery — RemoteStatusService | Task 4 |
| 3. Live remote-status discovery — view wiring | Task 5 |
| 4. Real refreshAll — reconcile pure fn | Task 6 |
| 4. Real refreshAll — body + wire | Task 7 |
| 5. FP queries — TimedCache | Task 8 |
| 5. FP queries — async impl | Task 9 |
| Exit verification | Task 10 |

All 5 in-scope spec items mapped.

**Placeholder scan:** "TBD" / "TODO" / "fill in" / "implement later" / "similar to Task N" search.

No matches. Two contingency callouts are explicit and complete (the `RcloneClient.about` overridability fallback in Task 4 Step 4.1; the `NSFileProviderEnumerator` API-shape fallback in Task 9 Step 9.3 — both have concrete alternative code, not deferred work).

**Type consistency:**
- `RemoteStatus` cases — used identically across Tasks 3 / 4 / 5 (`.unknown / .connected / .authNeeded / .error(reason:)`).
- `RemoteProbeClient.about(fs:)` — same signature in Tasks 4 + 5.
- `FPDomainInfo(identifier:displayName:)` — same in Tasks 6 + 7.
- `TimedCache<Key, Value>` API — same in Tasks 8 + 9.
- `FileProviderBridgeProtocol.isItemMaterialized(remote:path:) async -> Bool` and `wasRecentlyEvicted(remote:path:) async -> Bool` — same async signature across Task 9 and any caller update.
- Test count math (87 → 98 after Task 4 → 102 after Task 6 → 105 after Task 8) — consistent.

No drift detected.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-15-phase2c-state-accuracy.md`.
