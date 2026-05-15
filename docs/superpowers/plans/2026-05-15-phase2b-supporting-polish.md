# Phase 2b: Supporting Screens Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild Onboarding, Settings, CopySync screens against the foundation. Add `OnboardingCard` primitive JIT. Manually verify a first-launch-in-90-seconds wedge end-to-end before merge.

**Architecture:** Sequential per-screen with JIT primitive extraction (Onboarding → Settings → CopySync). Onboarding gets a progressive-card layout (reference: macOS Setup Assistant). Settings stays on TabView (Mail/Safari/Xcode pattern). CopySync becomes a focused one-shot form (Pages Export pattern).

**Tech Stack:** Swift 6 strict concurrency, SwiftUI on macOS 15+, `@Observable`, Swift Testing (`import Testing`), XcodeGen, RcloneKit local package.

**Parent spec:** `docs/superpowers/specs/2026-05-15-phase2b-supporting-polish-design.md`

---

## Conventions

- All new sources under `Nimbus/Nimbus/`. All new tests under `Nimbus/NimbusTests/`.
- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`).
- Snapshot tests use existing `SnapshotHelpers` (perceptual-hash comparison). PNG fixtures in `Nimbus/NimbusTests/Fixtures/`. `NIMBUS_SNAPSHOT_RECORD=1` records.
- After source / `project.yml` edits: `cd Nimbus && xcodegen generate` from repo root.
- Build: `xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' build`
- Test: same command with `test`.
- Commit prefix: `feat(swiftui):`, `fix(swiftui):`, `test(swiftui):`, `refactor(swiftui):`, `chore(swiftui):`.

## Existing-state notes the implementer must know

- `AppSettings` has: `rcloneBinaryPath`, `rclonePort`, `bandwidthLimit` (String), `concurrentTransfers` (Int), `onboardingComplete` (Bool), `appearance` (`.system / .light / .dark`). **No `showInMenuBar` field** — the spec mentioned it but we drop it from Phase 2b scope (adding a new menu-bar mode is out of scope).
- `Appearance` enum cases are `.system`, `.light`, `.dark` (not "auto").
- `LaunchAtLoginService` (`@Environment`) drives the launch-at-login toggle in GeneralSection. Methods: `refresh()`, `register()`, `unregister() async`. Property: `isEnabled`, `lastError`.
- `RcloneDaemon` has `port: Int` and `status` (cases `.idle`, `.starting`, `.connected`, `.error(String)`). **No `rcloneVersion`** — drop that row from the RcloneSection rebuild.
- `StorageUsageView` currently uses `FileManager`-based cache walk at `~/Library/Caches/app.casavargas.nimbus.FileProvider`. Reuse that path.
- Phase 2a's `SheetChrome`, `FormSection`, `FormRow`, `EmptyState`, `ProgressMeter`, `NimbusError` are available.

---

## Task 1: `OnboardingCard` primitive with snapshot tests

**Files:**
- Create: `Nimbus/Nimbus/Components/OnboardingCard.swift`
- Create: `Nimbus/NimbusTests/OnboardingCardTests.swift`

### Step 1.1: Write failing tests

- [ ] Create `Nimbus/NimbusTests/OnboardingCardTests.swift`:

```swift
import Testing
import SwiftUI
@testable import Nimbus

@Suite("OnboardingCard")
@MainActor
struct OnboardingCardTests {
    @Test func rendersPendingState() throws {
        let view = OnboardingCard(
            state: .pending,
            icon: "cloud",
            title: "Add a Remote",
            message: "Connect a cloud provider to get started.",
            primaryAction: nil,
            secondaryAction: nil
        )
        try SnapshotHelpers.assertSnapshot(
            view, size: CGSize(width: 520, height: 96), named: "OnboardingCard-pending"
        )
    }

    @Test func rendersInProgressState() throws {
        let view = OnboardingCard(
            state: .inProgress,
            icon: "bolt",
            title: "Rclone Daemon",
            message: "Connecting to rclone…",
            primaryAction: nil,
            secondaryAction: nil
        )
        try SnapshotHelpers.assertSnapshot(
            view, size: CGSize(width: 520, height: 96), named: "OnboardingCard-inProgress"
        )
    }

    @Test func rendersCompleteState() throws {
        let view = OnboardingCard(
            state: .complete,
            icon: "cloud",
            title: "Add a Remote",
            message: "Connected to gdrive.",
            primaryAction: nil,
            secondaryAction: .init(label: "Mount it for Finder →", perform: {})
        )
        try SnapshotHelpers.assertSnapshot(
            view, size: CGSize(width: 520, height: 120), named: "OnboardingCard-complete"
        )
    }

    @Test func rendersActionRequiredState() throws {
        let view = OnboardingCard(
            state: .actionRequired,
            icon: "cloud",
            title: "Add a Remote",
            message: "Connect a cloud provider to get started.",
            primaryAction: .init(label: "Add Remote", perform: {}),
            secondaryAction: nil
        )
        try SnapshotHelpers.assertSnapshot(
            view, size: CGSize(width: 520, height: 96), named: "OnboardingCard-actionRequired"
        )
    }
}
```

### Step 1.2: Run tests; expect compile failure

```bash
cd /Volumes/DATA/CasaVargas/Nimbus && cd Nimbus && xcodegen generate && cd .. && \
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' test \
  -only-testing:NimbusTests/OnboardingCardTests 2>&1 | tail -15
```

Expected: "cannot find 'OnboardingCard' in scope".

### Step 1.3: Implement `OnboardingCard.swift`

- [ ] Create `Nimbus/Nimbus/Components/OnboardingCard.swift`:

```swift
import SwiftUI

enum OnboardingCardState: Equatable, Sendable {
    case pending
    case inProgress
    case complete
    case actionRequired
}

/// Progressive state-machine card for the Onboarding flow.
/// Reference: macOS Setup Assistant (iCloud / Apple ID setup) step cards.
struct OnboardingCard: View {
    let state: OnboardingCardState
    let icon: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let primaryAction: ActionConfig?
    let secondaryAction: ActionConfig?

    struct ActionConfig {
        let label: LocalizedStringKey
        let perform: () -> Void
    }

    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.m) {
            stateIndicator
                .frame(width: 24, height: 24)

            Image(systemName: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)
                .foregroundStyle(iconTint)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(DesignSystem.Color.semantic.textPrimary)
                Text(message)
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                if state == .complete, let secondaryAction {
                    Button {
                        secondaryAction.perform()
                    } label: {
                        Text(secondaryAction.label)
                            .font(DesignSystem.Typography.callout)
                            .foregroundStyle(DesignSystem.Color.semantic.accent)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }

            Spacer()

            if state == .actionRequired, let primaryAction {
                Button {
                    primaryAction.perform()
                } label: {
                    Text(primaryAction.label)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
        }
        .padding(DesignSystem.Spacing.l)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.card, style: .continuous)
                .fill(DesignSystem.Color.semantic.surfaceSubtle)
        )
        .accessibilityElement(children: .combine)
        .accessibilityValue(accessibilityValue)
    }

    @ViewBuilder
    private var stateIndicator: some View {
        switch state {
        case .pending:
            Circle()
                .strokeBorder(DesignSystem.Color.semantic.textTertiary, lineWidth: 1.5)
        case .inProgress:
            ProgressView()
                .controlSize(.small)
        case .complete:
            Image(systemName: "checkmark.circle.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(DesignSystem.Color.semantic.statusOK)
        case .actionRequired:
            Circle()
                .fill(DesignSystem.Color.semantic.accent)
        }
    }

    private var iconTint: Color {
        switch state {
        case .actionRequired: return DesignSystem.Color.semantic.statusInfo
        case .complete: return DesignSystem.Color.semantic.statusOK
        default: return DesignSystem.Color.semantic.textSecondary
        }
    }

    private var accessibilityValue: String {
        switch state {
        case .pending: return "Pending"
        case .inProgress: return "In progress"
        case .complete: return "Complete"
        case .actionRequired: return "Action required"
        }
    }
}
```

### Step 1.4: Record fixtures + verify

```bash
NIMBUS_SNAPSHOT_RECORD=1 xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus \
  -destination 'platform=macOS' test -only-testing:NimbusTests/OnboardingCardTests 2>&1 | tail -10
```

Open `OnboardingCard-pending.png`, `OnboardingCard-inProgress.png`, `OnboardingCard-complete.png`, `OnboardingCard-actionRequired.png`. Verify each renders the correct state indicator + icon + title + message + (optional) action button or sub-CTA.

```bash
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' test \
  -only-testing:NimbusTests/OnboardingCardTests 2>&1 | tail -10
```

Expected: 4 tests pass.

### Step 1.5: Full suite no-regression check

```bash
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' test 2>&1 | \
  grep -E '(Test run|TEST SUCCEEDED|TEST FAILED)' | tail -3
```

Expected: 86 tests pass (82 baseline + 4 OnboardingCard).

### Step 1.6: Commit

```bash
git add Nimbus/Nimbus/Components/OnboardingCard.swift \
        Nimbus/NimbusTests/OnboardingCardTests.swift \
        Nimbus/NimbusTests/Fixtures \
        Nimbus/Nimbus.xcodeproj
git commit -m "feat(swiftui): add OnboardingCard primitive with 4-state machine

- States: .pending / .inProgress / .complete / .actionRequired
- Leading status indicator: outline circle / spinner / checkmark / accent dot
- Icon + title (headline) + message (body) + optional primary action button
- Sub-CTA (link-style) only visible on .complete state
- Reference: macOS Setup Assistant step cards
- 4 snapshot tests per state"
```

---

## Task 2: Rebuild `OnboardingView` with progressive card stack

**Files:**
- Replace: `Nimbus/Nimbus/Views/Onboarding/OnboardingView.swift`

### Step 2.1: Read the existing OnboardingView to capture state and call sites

```bash
cat /Volumes/DATA/CasaVargas/Nimbus/Nimbus/Nimbus/Views/Onboarding/OnboardingView.swift
```

Note the existing environment dependencies (`AppSettings`, `RcloneDaemon`) and any state currently being tracked (e.g., `remotes`, `showAddRemote`).

### Step 2.2: Replace `OnboardingView.swift`

- [ ] Write new content:

```swift
import SwiftUI
import RcloneKit

struct OnboardingView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(RcloneDaemon.self) private var daemon
    @Environment(MountConfigStore.self) private var mountStore

    @State private var remotes: [String] = []
    @State private var loadingRemotes = false
    @State private var showAddRemote = false
    @State private var showAddMount = false

    private var hasRemotes: Bool { !remotes.isEmpty }
    private var hasMounts: Bool { !mountStore.configs.isEmpty }
    private var canShowMountCard: Bool { hasRemotes }
    private var canShowDoneCard: Bool { hasRemotes && hasMounts }

    var body: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Spacing.l) {
                hero
                cardStack
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, DesignSystem.Spacing.xl)
            .padding(.vertical, DesignSystem.Spacing.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Color.semantic.surface)
        .sheet(isPresented: $showAddRemote) {
            AddRemoteSheet(client: daemon.client, onDismiss: {
                Task { await refreshRemotes() }
            })
        }
        .sheet(isPresented: $showAddMount) {
            // Placeholder — Task 3 wires this with the right MountsViewModel reference.
            AddMountSheet(viewModel: makeMountsViewModel())
        }
        .task(id: daemon.status) {
            if daemon.status == .connected {
                await refreshRemotes()
            }
        }
    }

    private var hero: some View {
        VStack(spacing: DesignSystem.Spacing.m) {
            Image(systemName: "cloud")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .foregroundStyle(DesignSystem.Color.semantic.statusInfo)
            Text("Welcome to Nimbus")
                .font(DesignSystem.Typography.largeTitle.bold())
                .foregroundStyle(DesignSystem.Color.semantic.textPrimary)
            Text("Your cloud storage, managed natively.")
                .font(DesignSystem.Typography.title3)
                .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
        }
        .padding(.bottom, DesignSystem.Spacing.l)
    }

    @ViewBuilder
    private var cardStack: some View {
        daemonCard
            .transition(.opacity.combined(with: .move(edge: .top)))

        if daemon.status == .connected {
            addRemoteCard
                .transition(.opacity.combined(with: .move(edge: .top)))
        }

        if canShowMountCard {
            addMountCard
                .transition(.opacity.combined(with: .move(edge: .top)))
        }

        if canShowDoneCard {
            doneCard
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    // MARK: - Cards

    private var daemonCard: some View {
        OnboardingCard(
            state: daemonCardState,
            icon: "bolt",
            title: "Rclone Daemon",
            message: daemonCardMessage,
            primaryAction: daemonRetryAction,
            secondaryAction: nil
        )
    }

    private var daemonCardState: OnboardingCardState {
        switch daemon.status {
        case .idle, .starting: return .inProgress
        case .connected: return .complete
        case .error: return .actionRequired
        }
    }

    private var daemonCardMessage: LocalizedStringKey {
        switch daemon.status {
        case .idle: return "Waiting to start…"
        case .starting: return "Connecting to rclone…"
        case .connected: return "Rclone is ready."
        case .error(let message): return LocalizedStringKey(message)
        }
    }

    private var daemonRetryAction: OnboardingCard.ActionConfig? {
        guard case .error = daemon.status else { return nil }
        return .init(label: "Retry", perform: {
            Task { await daemon.retry(binaryPath: settings.rcloneBinaryPath) }
        })
    }

    private var addRemoteCard: some View {
        OnboardingCard(
            state: hasRemotes ? .complete : .actionRequired,
            icon: "cloud",
            title: "Add a Remote",
            message: hasRemotes
                ? LocalizedStringKey("Connected to \(remotes.first ?? "your provider").")
                : LocalizedStringKey("Connect a cloud provider to get started."),
            primaryAction: hasRemotes ? nil : .init(label: "Add Remote", perform: { showAddRemote = true }),
            secondaryAction: hasRemotes ? .init(label: "Mount it for Finder →", perform: { showAddMount = true }) : nil
        )
    }

    private var addMountCard: some View {
        OnboardingCard(
            state: hasMounts ? .complete : .actionRequired,
            icon: "externaldrive",
            title: "Mount Your Remote",
            message: hasMounts
                ? LocalizedStringKey("Mounted at \(firstMountPath).")
                : LocalizedStringKey("Mount the remote to access it in Finder."),
            primaryAction: hasMounts ? nil : .init(label: "Add Mount", perform: { showAddMount = true }),
            secondaryAction: hasMounts ? .init(label: "Browse it →", perform: { finish() }) : nil
        )
    }

    private var doneCard: some View {
        OnboardingCard(
            state: .actionRequired,
            icon: "checkmark.seal.fill",
            title: "You're All Set",
            message: "Nimbus is ready to manage your cloud storage.",
            primaryAction: .init(label: "Done", perform: { finish() }),
            secondaryAction: nil
        )
    }

    // MARK: - Actions

    private var firstMountPath: String {
        mountStore.configs.first?.mountPoint ?? ""
    }

    private func finish() {
        settings.onboardingComplete = true
    }

    private func refreshRemotes() async {
        loadingRemotes = true
        defer { loadingRemotes = false }
        do {
            let names = try await daemon.client.listRemotes()
            withAnimation(DesignSystem.Motion.smooth) {
                remotes = names
            }
        } catch {
            // Silent — daemon error state surfaces via daemon.status, not here.
        }
    }

    private func makeMountsViewModel() -> MountsViewModel {
        // MountsViewModel takes the daemon client. We only need it to populate
        // remote names in the picker; AddMountSheet calls configStore.addConfig
        // directly on Save, so no other VM state is needed.
        MountsViewModel(client: daemon.client)
    }
}
```

### Step 2.3: Build, verify, commit

```bash
cd Nimbus && xcodegen generate && cd .. && \
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' build 2>&1 | tail -5
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' test 2>&1 | \
  grep -E '(Test run|TEST SUCCEEDED|TEST FAILED)' | tail -3
```

Expected: build succeeds; 86 tests pass.

If `MountsViewModel` has a different init signature than `(client:)`, adapt accordingly.

```bash
git add Nimbus/Nimbus/Views/Onboarding/OnboardingView.swift Nimbus/Nimbus.xcodeproj
git commit -m "feat(swiftui): rebuild OnboardingView as progressive card stack

- Hero header (cloud icon + Welcome to Nimbus + subtitle) routed through
  DesignSystem.Typography largeTitle / title3
- Card stack reveals in sequence:
  - Daemon (always visible) tracks daemon.status -> .inProgress / .complete /
    .actionRequired (with Retry CTA on error)
  - Add Remote (reveals after daemon connects) tracks remotes.isEmpty
  - Mount (reveals after a remote exists) tracks mountStore.configs.isEmpty
  - You're All Set (reveals after a mount exists) with Done -> sets
    settings.onboardingComplete = true
- Smooth transitions via DesignSystem.Motion.smooth
- ScrollView container with maxWidth 560 for centered layout
- Sub-CTAs from .complete cards trigger next-step actions"
```

---

## Task 3: Onboarding wedge integration polish

**Files:**
- Modify: `Nimbus/Nimbus/Views/Onboarding/OnboardingView.swift` (auto-mount and "Browse it" hook)

### Step 3.1: Ensure auto-mount on save during onboarding flow

The wedge requires the new mount to come up automatically. `AddMountSheet` already has an `autoMount` toggle — we want it defaulted to `true` for the onboarding flow.

- [ ] Two options:
  - **Pre-fill via a closure passed to `AddMountSheet`** — invasive, requires sheet API change.
  - **After `showAddMount` dismisses, find the newly-added MountConfig and call `mountManager.mountConfig(_:)`** — simpler.

Pick the second option. Inject `@Environment(MountManager.self) private var mountManager` and add this method:

```swift
private func attemptAutoMount() async {
    // If a new mount was added that isn't yet mounted, mount it now.
    for config in mountStore.configs where !mountManager.mountedIDs.contains(config.id) {
        try? await mountManager.mountConfig(config)
    }
}
```

Wire it into the `AddMountSheet` dismiss:

```swift
.sheet(isPresented: $showAddMount) {
    AddMountSheet(viewModel: makeMountsViewModel())
}
.onChange(of: mountStore.configs.count) { _, _ in
    Task { await attemptAutoMount() }
}
```

### Step 3.2: Wire the "Browse it →" sub-CTA on the Mount card to finish onboarding

The mount card's sub-CTA already calls `finish()` per Task 2's implementation. Verify by inspecting Task 2's code — `secondaryAction: hasMounts ? .init(label: "Browse it →", perform: { finish() }) : nil`. No change needed if this is already in place.

### Step 3.3: Build + commit

```bash
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' test 2>&1 | \
  grep -E '(Test run|TEST SUCCEEDED|TEST FAILED)' | tail -3
```

Expected: 86 tests pass.

```bash
git add Nimbus/Nimbus/Views/Onboarding/OnboardingView.swift
git commit -m "feat(swiftui): Onboarding auto-mounts new configs for wedge flow

After AddMountSheet adds a MountConfig, onChange watches mountStore.configs
and calls MountManager.mountConfig(_:) for any unmounted config. Lets the
wedge demo flow seamlessly from Add Mount -> mounted in Finder without an
extra user tap."
```

---

## Task 4: Settings window resize + `SettingsView` shell

**Files:**
- Replace: `Nimbus/Nimbus/Views/Settings/SettingsView.swift`

### Step 4.1: Replace `SettingsView.swift`

```swift
import SwiftUI

enum SettingsTab: Hashable {
    case general, appearance, transfers, rclone, storage, about
}

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSection()
                .tag(SettingsTab.general)
                .tabItem { Label("General", systemImage: "gearshape") }

            AppearanceSection()
                .tag(SettingsTab.appearance)
                .tabItem { Label("Appearance", systemImage: "paintbrush") }

            TransferSection()
                .tag(SettingsTab.transfers)
                .tabItem { Label("Transfers", systemImage: "arrow.up.arrow.down") }

            RcloneSection()
                .tag(SettingsTab.rclone)
                .tabItem { Label("Rclone", systemImage: "terminal") }

            StorageUsageView()
                .tag(SettingsTab.storage)
                .tabItem { Label("Storage", systemImage: "internaldrive") }

            AboutSection()
                .tag(SettingsTab.about)
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 360)
    }
}
```

Drop the outer `.padding()` — section panes provide their own internal padding now.

### Step 4.2: Verify

```bash
cd Nimbus && xcodegen generate && cd .. && \
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: build succeeds. Tests still pass (no behavior changes).

### Step 4.3: Commit

```bash
git add Nimbus/Nimbus/Views/Settings/SettingsView.swift Nimbus/Nimbus.xcodeproj
git commit -m "feat(swiftui): Settings window resized to 520x360

Previous size 450x250 was too cramped for FormSection layouts.
520x360 provides comfortable breathing room across all six panes.
Outer padding dropped — each section provides its own internal padding."
```

---

## Task 5: `GeneralSection` rebuild

**Files:**
- Replace: `Nimbus/Nimbus/Views/Settings/GeneralSection.swift`

### Step 5.1: Replace `GeneralSection.swift`

```swift
import SwiftUI

struct GeneralSection: View {
    @Environment(LaunchAtLoginService.self) private var launchAtLogin

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.l) {
            FormSection(title: "Application", footer: nil) {
                FormRow(label: "Launch at Login", help: nil) {
                    Toggle("", isOn: launchAtLoginBinding)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }
            if let error = launchAtLogin.lastError {
                Text(verbatim: error)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Color.semantic.statusError)
            }
            Spacer()
        }
        .padding(DesignSystem.Spacing.xl)
        .onAppear { launchAtLogin.refresh() }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin.isEnabled },
            set: { newValue in
                if newValue {
                    launchAtLogin.register()
                } else {
                    Task { await launchAtLogin.unregister() }
                }
            }
        )
    }
}
```

### Step 5.2: Verify + commit

```bash
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' build 2>&1 | tail -5
git add Nimbus/Nimbus/Views/Settings/GeneralSection.swift
git commit -m "feat(swiftui): rebuild GeneralSection with FormSection layout

- FormSection wrapping single FormRow for Launch at Login toggle
- Native Toggle(.switch), labelsHidden
- Error display via Text(verbatim:) in statusError color
- Spacer to push content to top; outer .padding(Spacing.xl)"
```

---

## Task 6: `AppearanceSection` rebuild

**Files:**
- Replace: `Nimbus/Nimbus/Views/Settings/AppearanceSection.swift`

### Step 6.1: Replace `AppearanceSection.swift`

```swift
import SwiftUI

struct AppearanceSection: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        VStack(alignment: .leading, spacing: DesignSystem.Spacing.l) {
            FormSection(title: "Appearance", footer: nil) {
                FormRow(label: "Color Scheme", help: nil) {
                    Picker("", selection: $settings.appearance) {
                        Text("System").tag(Appearance.system)
                        Text("Light").tag(Appearance.light)
                        Text("Dark").tag(Appearance.dark)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 240)
                }
            }
            Spacer()
        }
        .padding(DesignSystem.Spacing.xl)
    }
}
```

### Step 6.2: Verify + commit

```bash
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' build 2>&1 | tail -5
git add Nimbus/Nimbus/Views/Settings/AppearanceSection.swift
git commit -m "feat(swiftui): rebuild AppearanceSection with FormSection layout

- FormSection wrapping a single FormRow with segmented Picker
- Options: System / Light / Dark (matches Appearance enum cases)"
```

---

## Task 7: `TransferSection` rebuild with validation

**Files:**
- Replace: `Nimbus/Nimbus/Views/Settings/TransferSection.swift`

### Step 7.1: Replace `TransferSection.swift`

```swift
import SwiftUI

struct TransferSection: View {
    @Environment(AppSettings.self) private var settings
    @State private var bandwidthLimitDraft: String = ""
    @State private var bandwidthInvalid = false

    var body: some View {
        @Bindable var settings = settings

        VStack(alignment: .leading, spacing: DesignSystem.Spacing.l) {
            FormSection(
                title: "Transfers",
                footer: "Higher concurrency improves throughput but uses more memory."
            ) {
                FormRow(label: "Concurrent Transfers", help: nil) {
                    Stepper(value: $settings.concurrentTransfers, in: 1...32) {
                        Text(verbatim: "\(settings.concurrentTransfers)")
                    }
                    .frame(maxWidth: 160)
                }
                FormRow(label: "Bandwidth Limit", help: "e.g., 1M, 10M, 100k, or empty for unlimited.") {
                    TextField("Unlimited", text: $bandwidthLimitDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 160)
                        .onAppear { bandwidthLimitDraft = settings.bandwidthLimit }
                        .onChange(of: bandwidthLimitDraft) { _, newValue in
                            if isValidBandwidth(newValue) {
                                bandwidthInvalid = false
                                settings.bandwidthLimit = newValue
                            } else {
                                bandwidthInvalid = true
                            }
                        }
                }
            }
            if bandwidthInvalid {
                Text(verbatim: "Use a number with k/M/G suffix (e.g., 10M), or leave empty.")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Color.semantic.statusError)
            }
            Spacer()
        }
        .padding(DesignSystem.Spacing.xl)
    }

    /// Accepts empty (unlimited), or a number with optional k/M/G/T suffix.
    /// Examples that pass: "", "10M", "100k", "2.5G", "500".
    /// Examples that fail: "10MB", "abc", "10.5.5".
    private func isValidBandwidth(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return true }
        let pattern = #"^\d+(\.\d+)?[kMGTkmgt]?$"#
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }
}
```

### Step 7.2: Verify + commit

```bash
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' build 2>&1 | tail -5
git add Nimbus/Nimbus/Views/Settings/TransferSection.swift
git commit -m "feat(swiftui): rebuild TransferSection with FormSection + validation

- Stepper for Concurrent Transfers (1...32) with footer explainer
- Bandwidth Limit TextField with regex validation (empty or
  number + optional k/M/G/T suffix)
- Invalid value shown inline in statusError caption; valid values
  commit to settings.bandwidthLimit on every keystroke"
```

---

## Task 8: `RcloneSection` rebuild

**Files:**
- Replace: `Nimbus/Nimbus/Views/Settings/RcloneSection.swift`

### Step 8.1: Replace `RcloneSection.swift`

```swift
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct RcloneSection: View {
    @Environment(AppSettings.self) private var settings
    @Environment(RcloneDaemon.self) private var daemon
    @State private var showingFilePicker = false

    var body: some View {
        @Bindable var settings = settings

        VStack(alignment: .leading, spacing: DesignSystem.Spacing.l) {
            FormSection(title: "Binary", footer: nil) {
                FormRow(label: "Path", help: nil) {
                    HStack(spacing: DesignSystem.Spacing.s) {
                        Text(verbatim: settings.rcloneBinaryPath)
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Choose…") { showingFilePicker = true }
                            .controlSize(.small)
                    }
                    .frame(maxWidth: 320, alignment: .trailing)
                }
                FormRow(label: "Reveal in Finder", help: nil) {
                    Button("Reveal") {
                        NSWorkspace.shared.activateFileViewerSelecting(
                            [URL(fileURLWithPath: settings.rcloneBinaryPath)]
                        )
                    }
                    .controlSize(.small)
                }
            }
            FormSection(title: "Daemon", footer: nil) {
                FormRow(label: "Port", help: nil) {
                    Text(verbatim: "\(daemon.port)")
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                }
                FormRow(label: "Status", help: nil) {
                    daemonStatusBadge
                }
            }
            Spacer()
        }
        .padding(DesignSystem.Spacing.xl)
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.unixExecutable]
        ) { result in
            if case .success(let url) = result {
                settings.rcloneBinaryPath = url.path
            }
        }
    }

    @ViewBuilder
    private var daemonStatusBadge: some View {
        switch daemon.status {
        case .idle:
            Text("Not running")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
        case .starting:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Starting…")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
            }
        case .connected:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Color.semantic.statusOK)
        case .error(let msg):
            Label {
                Text(verbatim: msg)
                    .font(DesignSystem.Typography.caption)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .foregroundStyle(DesignSystem.Color.semantic.statusError)
        }
    }
}
```

Notes:
- We dropped the spec's "Version" row because `RcloneDaemon` doesn't expose a version property.
- We dropped the "Restart Daemon" button — `RcloneDaemon` doesn't expose a `restart()` async method per existing inspection. If it does on this branch, add a `Button("Restart") { Task { await daemon.restart() } }` row in the Daemon FormSection.

### Step 8.2: Verify + commit

```bash
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' build 2>&1 | tail -5
git add Nimbus/Nimbus/Views/Settings/RcloneSection.swift
git commit -m "feat(swiftui): rebuild RcloneSection with FormSection layout

- Binary section: Path (truncated middle, Choose... button via fileImporter
  of .unixExecutable) + Reveal in Finder action
- Daemon section: Port (read-only) + Status badge (Connected / Starting /
  Error / Not running) using inline status pill pattern
- Version + Restart Daemon rows from the spec are dropped because the
  daemon doesn't currently expose either; can be added later if those
  APIs land"
```

---

## Task 9: `StorageUsageView` rebuild

**Files:**
- Replace: `Nimbus/Nimbus/Views/Settings/StorageUsageView.swift`

### Step 9.1: Replace `StorageUsageView.swift`

```swift
import SwiftUI

struct StorageUsageView: View {
    @State private var totalCached: Int64 = 0
    @State private var isLoading = true
    @State private var showingClearConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.l) {
            FormSection(
                title: "Local Cache",
                footer: "Cached files speed up repeated access. Clearing removes only local copies — cloud files are unaffected."
            ) {
                FormRow(label: "Used", help: nil) {
                    if isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(verbatim: usageText)
                            .font(DesignSystem.Typography.body)
                            .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                    }
                }
                FormRow(label: "Clear Cache", help: nil) {
                    Button(role: .destructive) {
                        showingClearConfirmation = true
                    } label: {
                        Text("Clear…")
                    }
                    .controlSize(.small)
                    .disabled(totalCached == 0)
                }
            }
            Spacer()
        }
        .padding(DesignSystem.Spacing.xl)
        .task { await recompute() }
        .confirmationDialog(
            "Remove all cached files?",
            isPresented: $showingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Cache", role: .destructive) {
                Task { await clearCache() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Cloud files are unaffected. Files will re-download on access.")
        }
    }

    private var usageText: String {
        if totalCached == 0 { return "Empty" }
        return ByteCountFormatter.string(fromByteCount: totalCached, countStyle: .file)
    }

    private func cacheURL() -> URL? {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        return caches?.appendingPathComponent("app.casavargas.nimbus.FileProvider")
    }

    private func recompute() async {
        isLoading = true
        defer { isLoading = false }
        guard let url = cacheURL() else { totalCached = 0; return }
        let result = await Task.detached(priority: .utility) {
            guard let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else { return Int64(0) }
            var total: Int64 = 0
            for case let fileURL as URL in enumerator.allObjects {
                if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    total += Int64(size)
                }
            }
            return total
        }.value
        totalCached = result
    }

    private func clearCache() async {
        guard let url = cacheURL() else { return }
        try? FileManager.default.removeItem(at: url)
        await recompute()
    }
}
```

### Step 9.2: Verify + commit

```bash
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' build 2>&1 | tail -5
git add Nimbus/Nimbus/Views/Settings/StorageUsageView.swift
git commit -m "feat(swiftui): rebuild StorageUsageView with FormSection + real Clear Cache

- FormSection title 'Local Cache' with explanatory footer
- Used row shows ProgressView during scan, formatted byte count when done
- Clear Cache button (.destructive role) wired to confirmationDialog ->
  FileManager.removeItem(at:) on the FP cache directory
- Recomputes usage after clearing
- Disabled when totalCached == 0"
```

---

## Task 10: `AboutSection` rebuild

**Files:**
- Replace: `Nimbus/Nimbus/Views/Settings/AboutSection.swift`

### Step 10.1: Replace `AboutSection.swift`

```swift
import SwiftUI

struct AboutSection: View {
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.m) {
            Spacer()
            Image(systemName: "cloud")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .foregroundStyle(DesignSystem.Color.semantic.statusInfo)

            Text(verbatim: "Nimbus")
                .font(DesignSystem.Typography.largeTitle.bold())
                .foregroundStyle(DesignSystem.Color.semantic.textPrimary)

            Text(verbatim: "Version \(appVersion) (\(buildNumber))")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Color.semantic.textSecondary)

            Spacer()

            Link(destination: URL(string: "https://rclone.org/")!) {
                Text("Powered by rclone")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Color.semantic.accent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignSystem.Spacing.xl)
    }
}
```

### Step 10.2: Verify + commit

```bash
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' build 2>&1 | tail -5
git add Nimbus/Nimbus/Views/Settings/AboutSection.swift
git commit -m "feat(swiftui): rebuild AboutSection with centered chrome-less layout

- Large cloud icon (96pt) + Nimbus title (largeTitle.bold) + version/build
- Powered by rclone link to https://rclone.org/
- Spacers center the content vertically in the pane"
```

---

## Task 11: CopySync — `CopySyncView` rebuild

**Files:**
- Replace: `Nimbus/Nimbus/Views/CopySync/CopySyncView.swift`

### Step 11.1: Replace `CopySyncView.swift`

```swift
import SwiftUI
import RcloneKit

struct CopySyncView: View {
    @Environment(RcloneDaemon.self) private var daemon
    @Environment(TransferStore.self) private var store
    @State private var viewModel: CopySyncViewModel?

    @State private var operation: TransferOperation = .copy
    @State private var srcRemote = ""
    @State private var srcPath = ""
    @State private var dstRemote = ""
    @State private var dstPath = ""
    @State private var isRunning = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.l) {
                operationSection
                if operation == .sync {
                    DestructiveCallout(
                        message: "Sync will make the destination identical to the source. Files in the destination not in the source will be deleted."
                    )
                }
                pathsSection
                if let error = viewModel?.error {
                    EmptyState(
                        icon: "exclamationmark.triangle",
                        title: "Couldn't start",
                        messageVerbatim: error.message,
                        action: .init(label: "Dismiss", perform: { viewModel?.clearError() })
                    )
                    .frame(maxHeight: 160)
                }
                runRow
            }
            .padding(DesignSystem.Spacing.xl)
            .frame(maxWidth: 720)
        }
        .navigationTitle("Copy / Sync")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            let vm = CopySyncViewModel(client: daemon.client, store: store)
            viewModel = vm
            await vm.loadRemotes()
        }
    }

    private var operationSection: some View {
        FormSection(title: "Operation", footer: nil) {
            FormRow(label: "Mode", help: nil) {
                Picker("", selection: $operation) {
                    Text("Copy").tag(TransferOperation.copy)
                    Text("Sync").tag(TransferOperation.sync)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 200)
            }
        }
    }

    private var pathsSection: some View {
        FormSection(title: "Paths", footer: nil) {
            PathPicker(
                label: "Source",
                remoteNames: viewModel?.remoteNames ?? [],
                selectedRemote: $srcRemote,
                path: $srcPath
            )
            PathPicker(
                label: "Destination",
                remoteNames: viewModel?.remoteNames ?? [],
                selectedRemote: $dstRemote,
                path: $dstPath
            )
        }
    }

    private var runRow: some View {
        HStack {
            Spacer()
            Button(isRunning ? "Running…" : "Run") {
                Task { await run() }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!isValid || isRunning)
        }
    }

    private var isValid: Bool {
        !srcRemote.isEmpty && !dstRemote.isEmpty
    }

    private func run() async {
        guard let viewModel else { return }
        isRunning = true
        defer { isRunning = false }
        await viewModel.run(
            operation: operation,
            srcFs: "\(srcRemote):",
            srcRemote: srcPath,
            dstFs: "\(dstRemote):",
            dstRemote: dstPath
        )
    }
}

private struct DestructiveCallout: View {
    let message: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DesignSystem.Color.semantic.statusWarning)
            Text(message)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
            Spacer()
        }
        .padding(DesignSystem.Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.card, style: .continuous)
                .fill(DesignSystem.Color.semantic.statusWarning.opacity(0.10))
        )
    }
}
```

Notes:
- `CopySyncViewModel`'s `run(...)` signature and `clearError()` method are assumed to exist. If they don't, adapt to whatever the actual VM exposes (`grep -A5 'final class CopySyncViewModel' Nimbus/Nimbus/Nimbus/ViewModels/CopySyncViewModel.swift` to verify).
- Replaces the old TransferOperation.move case in the picker (only copy/sync are valid for the user-facing CopySync feature — move is internal to the drag-drop wedge).

### Step 11.2: Verify + commit

```bash
cd Nimbus && xcodegen generate && cd .. && \
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' test 2>&1 | \
  grep -E '(Test run|TEST SUCCEEDED|TEST FAILED)' | tail -3
git add Nimbus/Nimbus/Views/CopySync/CopySyncView.swift Nimbus/Nimbus.xcodeproj
git commit -m "feat(swiftui): rebuild CopySyncView with FormSection + DestructiveCallout

- FormSection(title: 'Operation') with segmented Picker (Copy / Sync)
- DestructiveCallout (file-private) renders warning when Sync selected:
  HStack with statusWarning triangle + caption + tinted background
- FormSection(title: 'Paths') with two PathPicker rows
- EmptyState-style error display (messageVerbatim) when viewModel.error
  is set; Dismiss CTA wired to viewModel.clearError()
- Run button: keyboardShortcut(.defaultAction), .borderedProminent, .large
  size, disabled until both remotes are picked
- ScrollView container; maxWidth 720 keeps the form readable on wide windows"
```

---

## Task 12: CopySync — `PathPicker` rebuild

**Files:**
- Replace: `Nimbus/Nimbus/Views/CopySync/PathPicker.swift`

### Step 12.1: Replace `PathPicker.swift`

```swift
import SwiftUI

struct PathPicker: View {
    let label: LocalizedStringKey
    let remoteNames: [String]
    @Binding var selectedRemote: String
    @Binding var path: String

    var body: some View {
        FormRow(label: label, help: nil) {
            HStack(spacing: DesignSystem.Spacing.s) {
                Picker("", selection: $selectedRemote) {
                    Text("Choose…").tag("")
                    ForEach(remoteNames, id: \.self) { name in
                        Text(verbatim: name).tag(name)
                    }
                }
                .labelsHidden()
                .frame(width: 140)

                TextField("/", text: $path)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
                    .disabled(selectedRemote.isEmpty)
            }
        }
    }
}
```

### Step 12.2: Verify + commit

```bash
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' test 2>&1 | \
  grep -E '(Test run|TEST SUCCEEDED|TEST FAILED)' | tail -3
git add Nimbus/Nimbus/Views/CopySync/PathPicker.swift
git commit -m "feat(swiftui): rebuild PathPicker as FormRow

- FormRow(label:, help: nil) with trailing HStack of:
  - Remote Picker (Choose... / remote names) at fixed 140pt
  - Path TextField with prompt '/' at maxWidth 200pt
- Path field disabled until a remote is selected
- All typography / spacing via DesignSystem tokens"
```

---

## Task 13: Phase 2b exit verification + first-launch wedge demo

**Files:**
- Create: `docs/superpowers/specs/<date>-phase2b-exit-gates.md`

### Step 13.1: Full test suite green

```bash
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' test 2>&1 | \
  grep -E '(Test run|TEST SUCCEEDED|TEST FAILED|lint-)' | tail -8
```

Expected: ≥ 86 tests pass (82 baseline + 4 OnboardingCard). Both lints OK.

### Step 13.2: Manual first-launch wedge

- [ ] To test the first-launch flow without uninstalling, reset `settings.onboardingComplete`:
  ```bash
  defaults delete app.casavargas.nimbus onboardingComplete
  ```
  Then launch Nimbus.
- [ ] Time the flow from app launch → Done button → main app:
  1. Hero + Daemon card visible immediately.
  2. Daemon card transitions to `.complete` within ~2s.
  3. Add Remote card reveals; tap **Add Remote**.
  4. Fill in a `local` provider (fastest for testing), tap Add Remote.
  5. Add Remote card transitions to `.complete`; Mount card reveals.
  6. Tap **Add Mount**, accept defaults, tap Add.
  7. Mount card transitions to `.complete`; Done card reveals.
  8. Tap **Done**; Onboarding dismisses.
- [ ] Target: ≤ 90 seconds. Note any non-native moments.

### Step 13.3: VoiceOver + Dynamic Type walkthrough

- [ ] VoiceOver: enable (⌘F5), navigate Onboarding cards → Settings tabs → CopySync form. Every interactive element announces a non-empty label.
- [ ] Dynamic Type XXXL: System Settings → Appearance → Text Size → XXXL. Confirm no layout breaks in Onboarding cards or Settings sections.

### Step 13.4: Side-by-side HIG comparisons

- [ ] Open Settings beside macOS Mail → Preferences. Note: should feel like the same family of UI.
- [ ] Open Onboarding (after `defaults delete`) beside System Settings → Apple ID Sign-In (a Setup-Assistant-style flow). Note proportions, card layout, progressive reveal.
- [ ] Open CopySync beside Pages → Export (File → Export To…). Compare form chrome, button placement, callout style.

### Step 13.5: Write exit-gate doc

Mirror Phase 2a's exit-gate doc style. Create `docs/superpowers/specs/2026-XX-XX-phase2b-exit-gates.md` with sections:
- Objective gates (✅ or explicit deferral)
- Subjective gates
- Wedge demo result (timing)
- Known carry-forwards (the Phase 2a ones still open, plus anything new from 2b)

### Step 13.6: Final commit

```bash
git add docs/superpowers/specs
git commit -m "docs: Phase 2b exit-gate verification

86+ tests pass, lints green, first-launch wedge verified manually at
<NN> seconds. Side-by-side comparisons against Mail Preferences /
Apple ID Setup Assistant / Pages Export note <N> divergences.

Carry-forwards still open: <list>."
```

---

## Plan self-review

**1. Spec coverage:**

| Spec section | Implementing task |
|--------------|-------------------|
| OnboardingCard primitive | Task 1 |
| OnboardingView rebuild | Task 2 |
| Onboarding wedge integration | Task 3 |
| Settings window resize + shell | Task 4 |
| GeneralSection rebuild | Task 5 |
| AppearanceSection rebuild | Task 6 |
| TransferSection rebuild + validation | Task 7 |
| RcloneSection rebuild | Task 8 |
| StorageUsageView rebuild | Task 9 |
| AboutSection rebuild | Task 10 |
| CopySync rebuild with DestructiveCallout | Task 11 |
| PathPicker rebuild | Task 12 |
| Exit verification + wedge demo | Task 13 |

All 13 implementation-order entries from the spec map to a task. No gaps.

**2. Placeholder scan:**

No "TBD" / "TODO" / "implement later" / "similar to Task N" / "add appropriate error handling" markers. Two explicit decisions documented (drop Version + Restart Daemon rows in RcloneSection because the daemon doesn't expose those APIs; drop `showInMenuBar` from GeneralSection because AppSettings doesn't have the field). Adaptation guidance is provided for fields that may not exactly match the existing models (`CopySyncViewModel.run` and `.clearError()`).

**3. Type consistency:**

- `OnboardingCardState` cases (`.pending`, `.inProgress`, `.complete`, `.actionRequired`) consistent in Tasks 1, 2.
- `OnboardingCard.ActionConfig(label:perform:)` consistent in Tasks 1, 2, 3.
- `DestructiveCallout(message:)` consistent in Task 11 (file-private).
- `Appearance` enum cases `.system / .light / .dark` consistent in Tasks 6.
- `FormSection(title:footer:content:)` + `FormRow(label:help:trailing:)` consistent across all Settings tasks (5–10) and Task 11.

No drift.

**4. Test count consistency:**

| Task | Tests added |
|------|---|
| 1 | 4 OnboardingCard snapshot tests |
| 2 | 0 (manual smoke) |
| 3 | 0 (wedge demo in Task 13) |
| 4 | 0 (no behavior changes) |
| 5–10 | 0 (manual side-by-side comparisons) |
| 11–12 | 0 (manual smoke) |
| 13 | 0 (exit-gate doc) |

Total new: 4 tests. With Phase 2a baseline 82, Phase 2b exit target ≥ 86 tests passing. Matches Step 13.1.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-15-phase2b-supporting-polish.md`.
