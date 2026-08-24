# Nimbus Settings Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** Replace the six sparse Settings panes with three coherent native panes and add working defaults for future remotes, mounts, transfers, notifications, history, and diagnostics.

**Architecture:** AppSettings stores lightweight scalar preferences in injected UserDefaults. Creation flows consume defaults once, while TransferStore delegates finished-history persistence and notifications to focused injectable services. SettingsView composes General, Transfers, and Advanced panes over those domain APIs.

**Tech Stack:** Swift 6, SwiftUI, Observation, Swift Testing, UserNotifications, OSLog, RcloneKit, XcodeGen.

**Spec:** docs/superpowers/specs/2026-08-24-settings-redesign-design.md

## Global Constraints

- macOS 15.0 minimum; Swift 6 strict concurrency.
- Use native SwiftUI controls and existing FormSection/FormRow components.
- Preferences apply immediately; there is no Apply button.
- New remote and mount defaults never mutate existing configurations.
- Transfer history is local JSON only; no cloud sync.
- Diagnostics exclude credentials, rclone configuration, remote names, paths, and filenames.
- No cache-size control, menu-bar visibility toggle, or reset-all action.
- Add files to Nimbus/project.yml sources through XcodeGen; regenerate Nimbus/Nimbus.xcodeproj after adding files.
- In every task that creates a Swift file, run cd Nimbus && xcodegen generate before the first RED test so the new test is part of the target.
- Follow TDD for every behavior task and make one focused conventional commit per task.
- Test snippets use named fixtures for readability; define each fixture in the same test file as a private helper with fixed dates, UUIDs, paths, and injected temporary directories. Do not read production UserDefaults, Application Support, notification center, or filesystem locations from tests.

---

## File Structure

**Create**

- Nimbus/Nimbus/State/SettingsPreferences.swift — stable preference enums.
- Nimbus/Nimbus/State/TransferHistoryFile.swift — versioned JSON persistence and retention pruning.
- Nimbus/Nimbus/Services/TransferNotificationService.swift — notification authorization and delivery boundary.
- Nimbus/Nimbus/Services/DiagnosticsService.swift — privacy-safe system information and Console opening.
- Nimbus/Nimbus/Views/Settings/GeneralSettingsView.swift — General pane composition.
- Nimbus/Nimbus/Views/Settings/TransferSettingsView.swift — Transfers pane composition and validation.
- Nimbus/Nimbus/Views/Settings/AdvancedSettingsView.swift — Advanced pane composition.
- Matching Nimbus/NimbusTests files for each behavior and pane snapshot.

**Modify**

- Nimbus/Nimbus/State/AppSettings.swift — injected defaults and new stored preferences.
- Nimbus/Nimbus/State/TransferStore.swift — persistence and notification integration.
- Nimbus/Nimbus/Services/RcloneDaemon.swift — active binary, version, restart-required, and restart APIs.
- Nimbus/Nimbus/Views/Mounts/AddMountSheet.swift — creation-only mount defaults.
- Nimbus/Nimbus/Views/Remotes/AddRemoteSheet.swift — post-create Finder integration.
- Nimbus/Nimbus/Views/Remotes/ImportConfigSheet.swift — post-import Finder integration.
- Nimbus/Nimbus/Views/Browser/ConfirmCopySheet.swift — explicit initial conflict policy.
- Nimbus/Nimbus/Views/Browser/BrowserView.swift and Nimbus/Nimbus/Views/ContentView.swift — construct CopyRequest from settings.
- Nimbus/Nimbus/NimbusApp.swift — inject new services and restore history.
- Nimbus/Nimbus/Views/Settings/SettingsView.swift — three-pane shell.
- Nimbus/project.yml and generated Nimbus/Nimbus.xcodeproj/project.pbxproj.

---

### Task 1: Typed Preference Storage

**Files:**
- Create: Nimbus/Nimbus/State/SettingsPreferences.swift
- Modify: Nimbus/Nimbus/State/AppSettings.swift
- Create: Nimbus/NimbusTests/AppSettingsTests.swift

**Interfaces:**
- Produces: MountAccessDefault, ConflictPolicy, TransferNotificationMode, TransferHistoryRetention.
- Produces AppSettings properties: addNewRemotesToFinder, newMountAccess, newMountAutoMount, defaultConflictPolicy, transferNotificationMode, transferHistoryRetention.
- Produces init(defaults: UserDefaults = .standard).

- [ ] **Step 1: Write failing defaults and round-trip tests**

    @Suite("AppSettings")
    struct AppSettingsTests {
        private func isolatedDefaults() -> UserDefaults {
            let name = "NimbusTests.AppSettings.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: name)!
            defaults.removePersistentDomain(forName: name)
            return defaults
        }

        @Test func curatedDefaults() {
            let defaults = isolatedDefaults()
            let settings = AppSettings(defaults: defaults)
            #expect(settings.addNewRemotesToFinder)
            #expect(settings.newMountAccess == .readWrite)
            #expect(settings.newMountAutoMount == false)
            #expect(settings.defaultConflictPolicy == .rename)
            #expect(settings.transferNotificationMode == .failuresOnly)
            #expect(settings.transferHistoryRetention == .sevenDays)
        }

        @Test func preferencesRoundTrip() {
            let defaults = isolatedDefaults()
            let first = AppSettings(defaults: defaults)
            first.newMountAccess = .readOnly
            first.transferHistoryRetention = .thirtyDays
            let second = AppSettings(defaults: defaults)
            #expect(second.newMountAccess == .readOnly)
            #expect(second.transferHistoryRetention == .thirtyDays)
        }
    }

- [ ] **Step 2: Run the tests and verify RED**

    xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' -only-testing:NimbusTests/AppSettingsTests test

Expected: compile failure because the new initializer, enums, and properties do not exist.

- [ ] **Step 3: Implement stable enums and injected defaults**

    enum MountAccessDefault: String, Codable, CaseIterable {
        case readWrite
        case readOnly
    }

    enum TransferNotificationMode: String, Codable, CaseIterable {
        case failuresOnly
        case allTransfers
        case off
    }

    enum TransferHistoryRetention: String, Codable, CaseIterable {
        case sevenDays
        case thirtyDays
        case forever
        case untilQuit
    }

Change AppSettings.defaults to an injected ObservationIgnored value, load every property with the approved default, and persist enum raw values in didSet. Reuse the existing ConflictPolicy raw-value enum rather than introducing a duplicate.

- [ ] **Step 4: Run AppSettingsTests and verify GREEN**

Run the command from Step 2. Expected: all AppSettings tests pass.

- [ ] **Step 5: Commit**

    git add Nimbus/Nimbus/State/SettingsPreferences.swift Nimbus/Nimbus/State/AppSettings.swift Nimbus/NimbusTests/AppSettingsTests.swift Nimbus/Nimbus.xcodeproj/project.pbxproj
    git commit -m "feat(settings): add curated preference storage"

---

### Task 2: Creation-Only Mount Defaults

**Files:**
- Modify: Nimbus/Nimbus/Views/Mounts/AddMountSheet.swift
- Create: Nimbus/NimbusTests/MountDefaultsTests.swift

**Interfaces:**
- Consumes: AppSettings.newMountAccess and AppSettings.newMountAutoMount.
- Produces: MountDraft.make(settings:editing:) returning initial VFSMode and autoMount values.

- [ ] **Step 1: Write failing creation/editing tests**

    @Test func newDraftUsesGlobalDefaults() {
        let settings = AppSettings(defaults: isolatedDefaults())
        settings.newMountAccess = .readOnly
        settings.newMountAutoMount = true
        let draft = MountDraft.make(settings: settings, editing: nil)
        #expect(draft.vfsMode == .readOnly)
        #expect(draft.autoMount)
    }

    @Test func editDraftPreservesConfiguration() {
        let existing = MountConfig(remote: "work:", mountPoint: "/Volumes/work",
                                   vfsMode: .readWrite, autoMount: false, backend: .nfs)
        let settings = AppSettings(defaults: isolatedDefaults())
        settings.newMountAccess = .readOnly
        settings.newMountAutoMount = true
        let draft = MountDraft.make(settings: settings, editing: existing)
        #expect(draft.vfsMode == .readWrite)
        #expect(draft.autoMount == false)
    }

- [ ] **Step 2: Run and verify RED**

    xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' -only-testing:NimbusTests/MountDefaultsTests test

Expected: compile failure because MountDraft does not exist.

- [ ] **Step 3: Implement MountDraft and initialize sheet state once**

    struct MountDraft: Equatable {
        var vfsMode: VFSMode
        var autoMount: Bool

        static func make(settings: AppSettings, editing: MountConfig?) -> Self {
            if let editing {
                return Self(vfsMode: editing.vfsMode, autoMount: editing.autoMount)
            }
            return Self(
                vfsMode: settings.newMountAccess == .readOnly ? .readOnly : .readWrite,
                autoMount: settings.newMountAutoMount
            )
        }
    }

Inject AppSettings into AddMountSheet and apply the draft inside its existing task. Do not read defaults after initialization.

- [ ] **Step 4: Run MountDefaultsTests and the existing MountRowTests**

Expected: all pass.

- [ ] **Step 5: Commit**

    git add Nimbus/Nimbus/Views/Mounts/AddMountSheet.swift Nimbus/NimbusTests/MountDefaultsTests.swift Nimbus/Nimbus.xcodeproj/project.pbxproj
    git commit -m "feat(settings): apply defaults to new mounts"

---

### Task 3: Finder Integration For New Remotes

**Files:**
- Create: Nimbus/Nimbus/Services/NewRemoteIntegration.swift
- Modify: Nimbus/Nimbus/Views/Remotes/AddRemoteSheet.swift
- Modify: Nimbus/Nimbus/Views/Remotes/ImportConfigSheet.swift
- Create: Nimbus/NimbusTests/NewRemoteIntegrationTests.swift

**Interfaces:**
- Consumes: AppSettings.addNewRemotesToFinder.
- Produces protocol FileProviderDomainAdding with addDomain(identifier:displayName:) async throws.
- Produces NewRemoteIntegration.integrate(names:addToFinder:) async -> [RemoteIntegrationFailure].

- [ ] **Step 1: Write failing success, disabled, and partial-failure tests**

    @Test func enabledRegistersEveryNewRemote() async {
        let bridge = DomainAdderSpy()
        let service = NewRemoteIntegration(domainAdder: bridge)
        let failures = await service.integrate(names: ["a", "b"], addToFinder: true)
        #expect(await bridge.names == ["a", "b"])
        #expect(failures.isEmpty)
    }

    @Test func disabledRegistersNothing() async {
        let bridge = DomainAdderSpy()
        let failures = await NewRemoteIntegration(domainAdder: bridge)
            .integrate(names: ["a"], addToFinder: false)
        #expect(await bridge.names.isEmpty)
        #expect(failures.isEmpty)
    }

- [ ] **Step 2: Run and verify RED**

    xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' -only-testing:NimbusTests/NewRemoteIntegrationTests test

- [ ] **Step 3: Implement the integration boundary**

    struct RemoteIntegrationFailure: Identifiable, Equatable {
        let remoteName: String
        let message: String
        var id: String { remoteName }
    }

    @MainActor
    struct NewRemoteIntegration {
        let domainAdder: any FileProviderDomainAdding
        func integrate(names: [String], addToFinder: Bool) async -> [RemoteIntegrationFailure]
    }

Make FileProviderBridge conform to FileProviderDomainAdding. AddRemoteSheet and ImportConfigSheet call the service only after each rclone create succeeds. Keep successful remotes if domain registration fails, show a warning listing failures, and provide Retry Finder Integration.

- [ ] **Step 4: Run NewRemoteIntegrationTests and remote view-model tests**

Expected: all pass.

- [ ] **Step 5: Commit**

    git add Nimbus/Nimbus/Services/NewRemoteIntegration.swift Nimbus/Nimbus/Services/FileProviderBridge.swift Nimbus/Nimbus/Views/Remotes/AddRemoteSheet.swift Nimbus/Nimbus/Views/Remotes/ImportConfigSheet.swift Nimbus/NimbusTests/NewRemoteIntegrationTests.swift Nimbus/Nimbus.xcodeproj/project.pbxproj
    git commit -m "feat(settings): apply Finder default to new remotes"

---

### Task 4: Default Copy Conflict Policy

**Files:**
- Modify: Nimbus/Nimbus/Views/Browser/ConfirmCopySheet.swift
- Modify: Nimbus/Nimbus/Views/Browser/BrowserView.swift
- Modify: Nimbus/Nimbus/Views/ContentView.swift
- Create: Nimbus/NimbusTests/CopyRequestTests.swift

**Interfaces:**
- Consumes: AppSettings.defaultConflictPolicy.
- Produces CopyRequest initializer requiring conflictPolicy.

- [ ] **Step 1: Write the failing initialization test**

    @Test func requestKeepsProvidedDefaultAndAllowsOverride() {
        var request = CopyRequest(sourceRemote: "a", target: target, items: items,
                                  conflictPolicy: .skip)
        #expect(request.conflictPolicy == .skip)
        request.conflictPolicy = .overwrite
        #expect(request.conflictPolicy == .overwrite)
    }

- [ ] **Step 2: Run and verify RED**

Run only CopyRequestTests. Expected: failure because the initializer still relies on a hidden .rename default.

- [ ] **Step 3: Require the policy and update both creation sites**

    init(sourceRemote: String, target: DropIntent.DropTarget,
         items: [DropIntent.Item], conflictPolicy: ConflictPolicy) {
        self.sourceRemote = sourceRemote
        self.target = target
        self.items = items
        self.conflictPolicy = conflictPolicy
    }

Pass settings.defaultConflictPolicy from BrowserView and ContentView. Leave ConfirmCopySheet binding behavior unchanged.

- [ ] **Step 4: Run CopyRequestTests and DragDropCoordinatorTests**

- [ ] **Step 5: Commit**

    git add Nimbus/Nimbus/Views/Browser/ConfirmCopySheet.swift Nimbus/Nimbus/Views/Browser/BrowserView.swift Nimbus/Nimbus/Views/ContentView.swift Nimbus/NimbusTests/CopyRequestTests.swift Nimbus/Nimbus.xcodeproj/project.pbxproj
    git commit -m "feat(settings): honor default conflict policy"

---

### Task 5: Versioned Transfer History

**Files:**
- Create: Nimbus/Nimbus/State/TransferHistoryFile.swift
- Modify: Nimbus/Nimbus/State/TransferStore.swift
- Modify: Nimbus/Nimbus/Views/Transfers/TransferRow.swift
- Modify: Nimbus/Nimbus/NimbusApp.swift
- Create: Nimbus/NimbusTests/TransferHistoryFileTests.swift
- Create: Nimbus/NimbusTests/TransferStorePersistenceTests.swift

**Interfaces:**
- Produces TransferRecord: Codable, Identifiable, Sendable.
- Produces protocol TransferHistoryPersisting with load, save, and quarantineCorruptFile.
- Produces TransferStore.restoreHistory(retention:) and applyRetention(_:).
- Changes Transfer identity to Nimbus UUID; rclone integer jobID remains a separate field used only for live RC calls.

- [ ] **Step 1: Write failing round-trip and retention tests**

    @Test func roundTripsFinishedRecords() async throws {
        let file = TransferHistoryFile(url: temporaryURL())
        try await file.save([finishedRecord])
        #expect(try await file.load() == [finishedRecord])
    }

    @Test func sevenDaysPrunesOlderRecords() {
        let kept = TransferHistoryPolicy.prune(
            [sixDaysOld, eightDaysOld], retention: .sevenDays, now: now
        )
        #expect(kept == [sixDaysOld])
    }

    @Test func activeTransfersAreNeverPersisted() async {
        let history = HistorySpy()
        let store = TransferStore(history: history, notifications: NotificationSpy())
        store.addTransfer(jobId: 1, operation: .copy, srcFs: "a:", dstFs: "b:")
        #expect(await history.savedRecords.isEmpty)
    }

    @Test func restoredAndNewJobsWithSameRcloneIDHaveDistinctIdentity() async {
        let store = makeStore(restoredJobID: 1)
        store.addTransfer(jobId: 1, operation: .copy, srcFs: "a:", dstFs: "b:")
        #expect(Set(store.transfers.map(\.id)).count == 2)
    }

- [ ] **Step 2: Run both new suites and verify RED**

Expected: compile failure for missing persistence types and injected TransferStore initializer.

- [ ] **Step 3: Implement records, atomic file I/O, pruning, and restoration**

    struct TransferRecord: Codable, Identifiable, Equatable, Sendable {
        let id: UUID
        let jobID: Int
        let operation: TransferOperation
        let source: String
        let destination: String
        let startedAt: Date
        let completedAt: Date
        let outcome: TransferOutcome
        let origin: TransferOrigin
    }

    struct Transfer: Identifiable {
        var id: UUID { nimbusUUID }
        let jobID: Int
        // Existing transfer fields remain unchanged.
    }

    protocol TransferHistoryPersisting: Sendable {
        func load() async throws -> [TransferRecord]
        func save(_ records: [TransferRecord]) async throws
        func quarantineCorruptFile() async
    }

Make TransferOperation, TransferOrigin, and the persisted TransferOutcome Codable. Use Application Support/Nimbus/transfer-history-v1.json and Data.write(options: .atomic). Store terminal records after completion/failure/cancellation, remove/clear operations, and retention changes. Until Nimbus Quits skips load and save. Bootstrap calls restoreHistory after settings initialization. Update all live status/progress/stop lookups to compare jobID rather than id.

- [ ] **Step 4: Run the new suites and all TransferStore/TransferRow tests**

- [ ] **Step 5: Commit**

    git add Nimbus/Nimbus/State/TransferHistoryFile.swift Nimbus/Nimbus/State/TransferStore.swift Nimbus/Nimbus/Views/Transfers/TransferRow.swift Nimbus/Nimbus/NimbusApp.swift Nimbus/NimbusTests/TransferHistoryFileTests.swift Nimbus/NimbusTests/TransferStorePersistenceTests.swift Nimbus/Nimbus.xcodeproj/project.pbxproj
    git commit -m "feat(transfers): persist retained transfer history"

---

### Task 6: Transfer Notifications

**Files:**
- Create: Nimbus/Nimbus/Services/TransferNotificationService.swift
- Modify: Nimbus/Nimbus/State/TransferStore.swift
- Modify: Nimbus/Nimbus/NimbusApp.swift
- Create: Nimbus/NimbusTests/TransferNotificationServiceTests.swift

**Interfaces:**
- Produces NotificationAuthorizationStatus and protocol TransferNotifying.
- Consumes TransferNotificationMode and terminal TransferRecord values.

- [ ] **Step 1: Write failing policy tests**

    @Test func failuresOnlySuppressesSuccess() async {
        let center = NotificationCenterSpy()
        let service = TransferNotificationService(center: center)
        await service.deliver(completedRecord, mode: .failuresOnly)
        #expect(await center.requests.isEmpty)
    }

    @Test func failuresOnlyDeliversFailure() async {
        let center = NotificationCenterSpy()
        let service = TransferNotificationService(center: center)
        await service.deliver(failedRecord, mode: .failuresOnly)
        #expect(await center.requests.count == 1)
    }

- [ ] **Step 2: Run and verify RED**

Run TransferNotificationServiceTests. Expected: missing service and protocol.

- [ ] **Step 3: Implement the injectable UserNotifications adapter**

    protocol TransferNotifying: Sendable {
        func authorizationStatus() async -> NotificationAuthorizationStatus
        func requestAuthorization() async throws -> Bool
        func deliver(_ record: TransferRecord, mode: TransferNotificationMode) async
    }

Use UNUserNotificationCenter only inside the concrete adapter. Notification body contains operation and outcome, never source/destination paths. TransferStore calls deliver only for completed or failed transitions; cancelled records never notify.

- [ ] **Step 4: Run notification and persistence suites**

- [ ] **Step 5: Commit**

    git add Nimbus/Nimbus/Services/TransferNotificationService.swift Nimbus/Nimbus/State/TransferStore.swift Nimbus/Nimbus/NimbusApp.swift Nimbus/NimbusTests/TransferNotificationServiceTests.swift Nimbus/Nimbus.xcodeproj/project.pbxproj
    git commit -m "feat(transfers): add configurable notifications"

---

### Task 7: Rclone Restart, Version, And Diagnostics

**Files:**
- Modify: Nimbus/Nimbus/Services/RcloneDaemon.swift
- Create: Nimbus/Nimbus/Services/DiagnosticsService.swift
- Create: Nimbus/NimbusTests/RcloneDaemonSettingsTests.swift
- Create: Nimbus/NimbusTests/DiagnosticsServiceTests.swift

**Interfaces:**
- Produces RcloneDaemon.activeBinaryPath, rcloneVersion, restartRequired(for:), restart(binaryPath:).
- Produces DiagnosticsService.systemInformation(daemon:) -> String and openLogs().

- [ ] **Step 1: Write failing state and privacy tests**

    @Test func changingConfiguredPathRequiresRestart() {
        let daemon = makeConnectedDaemon(activePath: "/a/rclone")
        #expect(daemon.restartRequired(for: "/b/rclone"))
        #expect(!daemon.restartRequired(for: "/a/rclone"))
    }

    @Test func diagnosticTextExcludesUserData() {
        let text = DiagnosticsService(info: fixedInfo).systemInformation(daemon: daemon)
        #expect(text.contains("Nimbus Version:"))
        #expect(!text.contains("remoteName"))
        #expect(!text.contains("/Users/"))
    }

- [ ] **Step 2: Run both suites and verify RED**

- [ ] **Step 3: Implement daemon APIs and safe diagnostics**

    func restartRequired(for configuredPath: String) -> Bool {
        status == .connected && activeBinaryPath != configuredPath
    }

    func restart(binaryPath: String) async {
        stop()
        await start(binaryPath: binaryPath)
    }

Capture activeBinaryPath only after Process.run succeeds. Query rclone version through a Process executing binaryPath with argument version and parse the first line off the main actor. Diagnostics uses only the approved fixed fields. openLogs launches Console with a Nimbus subsystem predicate; it does not generate a log archive.

- [ ] **Step 4: Run daemon/diagnostics suites and build Nimbus**

- [ ] **Step 5: Commit**

    git add Nimbus/Nimbus/Services/RcloneDaemon.swift Nimbus/Nimbus/Services/DiagnosticsService.swift Nimbus/NimbusTests/RcloneDaemonSettingsTests.swift Nimbus/NimbusTests/DiagnosticsServiceTests.swift Nimbus/Nimbus.xcodeproj/project.pbxproj
    git commit -m "feat(settings): add daemon diagnostics controls"

---

### Task 8: General Settings Pane

**Files:**
- Create: Nimbus/Nimbus/Views/Settings/GeneralSettingsView.swift
- Modify: Nimbus/Nimbus/Views/Settings/StorageUsageView.swift
- Remove after migration: Nimbus/Nimbus/Views/Settings/GeneralSection.swift
- Remove after migration: Nimbus/Nimbus/Views/Settings/AppearanceSection.swift
- Remove after migration: Nimbus/Nimbus/Views/Settings/AboutSection.swift
- Create: Nimbus/NimbusTests/GeneralSettingsViewTests.swift

**Interfaces:**
- Consumes AppSettings, LaunchAtLoginService, and cache-usage behavior.
- Produces the complete General destination view.

- [ ] **Step 1: Write failing snapshots for normal and cache-error states**

    @Test func rendersGeneralPane() throws {
        try SnapshotHelpers.assertSnapshot(
            GeneralSettingsView(model: fixtureModel),
            size: CGSize(width: 680, height: 450),
            named: "Settings-General"
        )
    }

    @Test func rendersCacheFailure() throws {
        try SnapshotHelpers.assertSnapshot(
            GeneralSettingsView(model: cacheFailureModel),
            size: CGSize(width: 680, height: 450),
            named: "Settings-General-cache-error"
        )
    }

- [ ] **Step 2: Run snapshots and verify RED**

- [ ] **Step 3: Build General from separate section views**

Compose ApplicationSettingsSection, FinderDefaultsSection, LocalStorageSettingsSection, and AboutSettingsSection inside a ScrollView. Appearance uses a menu picker. Clear Cache confirms, reports errors, and refreshes usage. The Finder footer says defaults apply only to future configurations. Render runtime errors and paths verbatim.

- [ ] **Step 4: Record fixtures, inspect PNGs, rerun without recording**

    NIMBUS_SNAPSHOT_RECORD=1 xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' -only-testing:NimbusTests/GeneralSettingsViewTests test

Inspect each new fixture, then rerun without NIMBUS_SNAPSHOT_RECORD. Expected: pass.

- [ ] **Step 5: Commit**

    git add Nimbus/Nimbus/Views/Settings Nimbus/NimbusTests/GeneralSettingsViewTests.swift Nimbus/NimbusTests/Fixtures Nimbus/Nimbus.xcodeproj/project.pbxproj
    git commit -m "feat(settings): build General preferences pane"

---

### Task 9: Transfers Settings Pane

**Files:**
- Create: Nimbus/Nimbus/Views/Settings/TransferSettingsView.swift
- Remove after migration: Nimbus/Nimbus/Views/Settings/TransferSection.swift
- Create: Nimbus/NimbusTests/TransferSettingsViewTests.swift
- Create: Nimbus/NimbusTests/BandwidthLimitValidatorTests.swift

**Interfaces:**
- Consumes AppSettings and TransferNotifying authorization status.
- Produces BandwidthLimitValidator.validate(_:) and the complete Transfers destination.

- [ ] **Step 1: Write failing validation and snapshot tests**

    @Test(arguments: ["", "500", "100k", "10M", "2.5G", "1T"])
    func acceptsRcloneLimits(_ value: String) {
        #expect(BandwidthLimitValidator.validate(value))
    }

    @Test(arguments: ["abc", "10MB", "1t", "-5M"])
    func rejectsInvalidLimits(_ value: String) {
        #expect(!BandwidthLimitValidator.validate(value))
    }

Add snapshots for normal, invalid-bandwidth, and notification-denied states.

- [ ] **Step 2: Run and verify RED**

- [ ] **Step 3: Implement pane and commit-on-submit validation**

Compose TransferPerformanceSection and TransferBehaviorSection. Keep a local bandwidth draft; persist only a valid trimmed value on submit or focus loss. Notification selection requests authorization when needed and shows Disabled in System Settings with an action when denied.

- [ ] **Step 4: Run validator tests, record/inspect snapshots, and rerun**

- [ ] **Step 5: Commit**

    git add Nimbus/Nimbus/Views/Settings/TransferSettingsView.swift Nimbus/NimbusTests/TransferSettingsViewTests.swift Nimbus/NimbusTests/BandwidthLimitValidatorTests.swift Nimbus/NimbusTests/Fixtures Nimbus/Nimbus.xcodeproj/project.pbxproj
    git commit -m "feat(settings): build Transfers preferences pane"

---

### Task 10: Advanced Pane, Shell, And End-To-End Wiring

**Files:**
- Create: Nimbus/Nimbus/Views/Settings/AdvancedSettingsView.swift
- Modify: Nimbus/Nimbus/Views/Settings/SettingsView.swift
- Remove after migration: Nimbus/Nimbus/Views/Settings/RcloneSection.swift
- Modify: Nimbus/Nimbus/NimbusApp.swift
- Modify: Nimbus/project.yml
- Regenerate: Nimbus/Nimbus.xcodeproj/project.pbxproj
- Create: Nimbus/NimbusTests/AdvancedSettingsViewTests.swift
- Create: Nimbus/NimbusTests/SettingsViewTests.swift

**Interfaces:**
- Consumes RcloneDaemon, AppSettings, DiagnosticsService, TransferNotificationService.
- Produces SettingsTab: CaseIterable with general, transfers, and advanced only.

- [ ] **Step 1: Write failing pane and shell snapshots**

    @Test func rendersAdvancedConnected() throws {
        try SnapshotHelpers.assertSnapshot(
            AdvancedSettingsView(model: connectedFixture),
            size: CGSize(width: 680, height: 450),
            named: "Settings-Advanced-connected"
        )
    }

    @Test func shellUsesThreeDestinations() {
        #expect(SettingsTab.allCases == [.general, .transfers, .advanced])
    }

Add snapshots for restart-required and daemon-error states.

- [ ] **Step 2: Run and verify RED**

- [ ] **Step 3: Implement Advanced and replace the shell**

Advanced composes RcloneSettingsSection, DaemonSettingsSection, and DiagnosticsSettingsSection. SettingsView uses exactly three toolbar tabs, frame width 680 and height 520, and existing semantic colors. NimbusApp injects the new services into Settings and main-window environments and restores transfer history during bootstrap.

- [ ] **Step 4: Regenerate the project and run focused tests**

    cd Nimbus
    xcodegen generate
    cd ..
    xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' -only-testing:NimbusTests/SettingsViewTests -only-testing:NimbusTests/AdvancedSettingsViewTests test

Expected: all pass after fixtures are recorded and visually inspected.

- [ ] **Step 5: Run full automated verification**

    xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' test
    xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' build
    git diff --check

Expected: test and build exit 0; no whitespace errors. Do not update unrelated snapshot fixtures to hide pre-existing failures.

- [ ] **Step 6: Run manual acceptance**

Launch the Debug app and verify:

1. Settings shows General, Transfers, Advanced only.
2. All panes render in light and dark mode with no clipping.
3. Keyboard traversal and VoiceOver labels follow visual order.
4. New/imported remote Finder behavior follows the toggle; existing domains remain unchanged.
5. New mount defaults apply; editing preserves its stored values.
6. New copy confirmation inherits the preferred conflict choice.
7. Notification denial shows the recovery action.
8. Finished history survives relaunch and prunes according to retention.
9. Rclone path change shows Restart Required; restart recovers or displays error.
10. Cache deletion reports success only after filesystem completion.

- [ ] **Step 7: Commit**

    git add Nimbus/Nimbus/Views/Settings Nimbus/Nimbus/NimbusApp.swift Nimbus/NimbusTests/AdvancedSettingsViewTests.swift Nimbus/NimbusTests/SettingsViewTests.swift Nimbus/NimbusTests/Fixtures Nimbus/project.yml Nimbus/Nimbus.xcodeproj/project.pbxproj
    git commit -m "feat(settings): ship redesigned preferences"
