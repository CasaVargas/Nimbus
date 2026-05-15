# Phase 2a: Operational Screens Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the Remotes, Mounts, and Transfers screens against the Phase 1 foundation with a deep HIG audit. Extract five shared primitives JIT (`NimbusError`, `FormSection`, `SheetChrome`, `StatusToggle`, `ProgressMeter`). Manually verify the setup-to-mount wedge end-to-end before merge.

**Architecture:** Sequential per-screen with JIT primitive extraction. Each screen migrates its ViewModel's `error: String?` → `NimbusError?` first, then rebuilds its views against `DesignSystem` tokens + new primitives. Apple references: Disk Utility (Mounts), System Settings (Add Remote / Login Items), Mail outbox (Transfers).

**Tech Stack:** Swift 6 strict concurrency, SwiftUI on macOS 15+, `@Observable`, Swift Testing (`import Testing`), XcodeGen (`Nimbus/project.yml`), RcloneKit local package.

**Parent spec:** `docs/superpowers/specs/2026-05-15-phase2a-operational-polish-design.md`

---

## Conventions

- All new sources live under `Nimbus/Nimbus/`.
- All new tests live under `Nimbus/NimbusTests/`.
- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`). Match the existing pattern.
- Snapshot tests use the existing `SnapshotHelpers` (`Nimbus/NimbusTests/Support/SnapshotHelpers.swift`) with perceptual-hash comparison. PNG fixtures land in `Nimbus/NimbusTests/Fixtures/`. First-run / `NIMBUS_SNAPSHOT_RECORD=1` env var records new fixtures.
- After any `project.yml` edit or new source file, run `cd Nimbus && xcodegen generate` from the repo root, then build/test.
- Build: `xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' build`
- Test: `xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' test`
- Test (single suite): append `-only-testing:NimbusTests/<SuiteName>` to the `test` command.
- Commit prefix style matches recent repo history: `feat(swiftui):`, `fix(swiftui):`, `test(swiftui):`, `refactor(swiftui):`, `chore(swiftui):`.

---

## Task 1: `NimbusError` + ViewModel migrations

**Files:**
- Create: `Nimbus/Nimbus/State/NimbusError.swift`
- Modify: `Nimbus/Nimbus/ViewModels/BrowserViewModel.swift` (alias)
- Modify: `Nimbus/Nimbus/ViewModels/RemotesViewModel.swift` (`String?` → `NimbusError?`)
- Modify: `Nimbus/Nimbus/ViewModels/MountsViewModel.swift` (`String?` → `NimbusError?`)
- Modify: `Nimbus/Nimbus/ViewModels/TransfersViewModel.swift` (`String?` → `NimbusError?`)
- Create: `Nimbus/NimbusTests/NimbusErrorTests.swift`

### Step 1.1: Write failing tests for `NimbusError`

- [ ] Create `Nimbus/NimbusTests/NimbusErrorTests.swift`:

```swift
import Testing
import Foundation
@testable import Nimbus

@Suite("NimbusError")
struct NimbusErrorTests {
    @Test func classifyAuthFailedFromCommonKeywords() {
        let cases = [
            "401 Unauthorized",
            "auth required",
            "Token expired",
            "Please sign in",
            "OAuth refresh failed",
        ]
        for message in cases {
            let err = NimbusError.classify(SimpleError(message))
            #expect(err.kind == .authFailed, "expected .authFailed for: \(message)")
            #expect(err.message == message)
        }
    }

    @Test func classifyNetworkFromCommonKeywords() {
        let cases = [
            "Network connection lost",
            "Cannot reach server",
            "Connection refused",
            "You appear to be offline",
        ]
        for message in cases {
            let err = NimbusError.classify(SimpleError(message))
            #expect(err.kind == .network, "expected .network for: \(message)")
        }
    }

    @Test func classifyOtherWhenNoKeywordsMatch() {
        let err = NimbusError.classify(SimpleError("Filesystem busy"))
        #expect(err.kind == .other)
        #expect(err.message == "Filesystem busy")
    }

    @Test func equatableSameKindAndMessage() {
        let a = NimbusError(kind: .authFailed, message: "401")
        let b = NimbusError(kind: .authFailed, message: "401")
        #expect(a == b)
    }

    @Test func equatableDifferentKind() {
        let a = NimbusError(kind: .authFailed, message: "x")
        let b = NimbusError(kind: .network, message: "x")
        #expect(a != b)
    }
}

private struct SimpleError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ m: String) { message = m }
}
```

### Step 1.2: Run tests; expect compile failure

- [ ] Run:

```bash
cd /Volumes/DATA/CasaVargas/Nimbus && cd Nimbus && xcodegen generate && cd .. && \
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' test \
  -only-testing:NimbusTests/NimbusErrorTests 2>&1 | tail -20
```

Expected: build fails with "cannot find 'NimbusError' in scope".

### Step 1.3: Implement `NimbusError`

- [ ] Create `Nimbus/Nimbus/State/NimbusError.swift`:

```swift
import Foundation

/// Typed error pattern shared across Nimbus view models. Generalizes Phase 1's
/// `BrowserError`. The three kinds map to distinct UI affordances:
/// - `.authFailed` → "Sign In Required" + Reconnect action
/// - `.network` → "Can't Reach Cloud" + Retry action
/// - `.other` → generic banner + Retry action
///
/// Classification is a substring heuristic over `localizedDescription`.
/// Phase 2a heuristic; richer mapping to rclone error codes can come in Phase 3.
struct NimbusError: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case authFailed
        case network
        case other
    }

    let kind: Kind
    let message: String

    static func classify(_ error: Error) -> NimbusError {
        let message = error.localizedDescription
        let lower = message.lowercased()

        let authSignals = ["auth", "unauthorized", "token", "sign in", "401", "403", "oauth"]
        if authSignals.contains(where: { lower.contains($0) }) {
            return NimbusError(kind: .authFailed, message: message)
        }

        let networkSignals = ["network", "connection", "offline", "reach", "unreachable"]
        if networkSignals.contains(where: { lower.contains($0) }) {
            return NimbusError(kind: .network, message: message)
        }

        return NimbusError(kind: .other, message: message)
    }
}
```

### Step 1.4: Run tests; expect pass

- [ ] Run:

```bash
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' test \
  -only-testing:NimbusTests/NimbusErrorTests 2>&1 | tail -10
```

Expected: 5 tests pass.

### Step 1.5: Migrate `BrowserViewModel` (typealias for backwards compat)

- [ ] Open `Nimbus/Nimbus/ViewModels/BrowserViewModel.swift`. Find the `BrowserError` struct declaration.

- [ ] Replace the existing `BrowserError` struct with a typealias to `NimbusError`:

```swift
typealias BrowserError = NimbusError
```

- [ ] Remove the existing `classifyError(_:)` private method on `BrowserViewModel` and replace its call site (`self.error = classifyError(error)`) with:

```swift
self.error = NimbusError.classify(error)
```

- [ ] Also: `BrowserError.Kind` references in `BrowserView.swift` still resolve via the typealias. Check that the existing `errorState(for: error, viewModel:)` `switch error.kind` cases (`.authFailed`, `.offline`, `.other`) still compile.

**Note:** `NimbusError.Kind` has cases `.authFailed`, `.network`, `.other` — note `.offline` was renamed to `.network`. Update `BrowserView.swift`'s switch:

```swift
case .network:
    EmptyState(
        icon: "wifi.slash",
        title: "Can't Reach Cloud",
        // ... same body, just renamed case
    )
```

Find every `case .offline` reference in `BrowserView.swift` and rename to `case .network`. There should be exactly one.

### Step 1.6: Migrate `RemotesViewModel`

- [ ] Open `Nimbus/Nimbus/ViewModels/RemotesViewModel.swift`. Change:

```swift
private(set) var error: String?
```

to:

```swift
private(set) var error: NimbusError?
```

- [ ] In `loadRemotes()`, change:

```swift
self.error = error.localizedDescription
```

to:

```swift
self.error = NimbusError.classify(error)
```

### Step 1.7: Migrate `MountsViewModel`

- [ ] Open `Nimbus/Nimbus/ViewModels/MountsViewModel.swift`. Make the same two edits:
  - `error: String?` → `error: NimbusError?`
  - `self.error = error.localizedDescription` → `self.error = NimbusError.classify(error)`

If `MountsViewModel` has multiple `catch` blocks each setting `error`, update them all.

### Step 1.8: Migrate `TransfersViewModel`

- [ ] Open `Nimbus/Nimbus/ViewModels/TransfersViewModel.swift`. Same two edits.

### Step 1.9: Update existing consumers that read `error` as `String`

- [ ] grep for views that read `viewModel.error` from any of the three viewmodels:

```bash
grep -rn 'remotesViewModel\.error\|mountsViewModel\.error\|transfersViewModel\.error\|\.error ?? \|if let error =' \
  Nimbus/Nimbus/Views/Remotes \
  Nimbus/Nimbus/Views/Mounts \
  Nimbus/Nimbus/Views/Transfers
```

- [ ] For each call site that did `Text(viewModel.error ?? "")` or similar, update to `Text(viewModel.error?.message ?? "")`. Don't add full error-state branches yet — those come in the per-screen rebuilds (Tasks 3/8/11).

### Step 1.10: Run full suite

```bash
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' test 2>&1 | grep -E '(Test run|TEST SUCCEEDED|TEST FAILED)' | tail -3
```

Expected: 55 + 5 = 60 tests pass.

### Step 1.11: Commit

```bash
git add Nimbus/Nimbus/State/NimbusError.swift \
        Nimbus/Nimbus/ViewModels/BrowserViewModel.swift \
        Nimbus/Nimbus/ViewModels/RemotesViewModel.swift \
        Nimbus/Nimbus/ViewModels/MountsViewModel.swift \
        Nimbus/Nimbus/ViewModels/TransfersViewModel.swift \
        Nimbus/Nimbus/Views/Browser/BrowserView.swift \
        Nimbus/Nimbus/Views/Remotes \
        Nimbus/Nimbus/Views/Mounts \
        Nimbus/Nimbus/Views/Transfers \
        Nimbus/NimbusTests/NimbusErrorTests.swift \
        Nimbus/Nimbus.xcodeproj
git commit -m "feat(swiftui): add NimbusError + migrate Remotes/Mounts/Transfers/Browser viewmodels

- NimbusError generalizes BrowserError with kinds: .authFailed, .network, .other
- BrowserError becomes a typealias to NimbusError (backwards compat)
- BrowserViewModel uses NimbusError.classify; .offline case renamed to .network
- RemotesViewModel, MountsViewModel, TransfersViewModel migrate
  error: String? -> NimbusError?
- 5 unit tests for classify heuristic + Equatable"
```

---

## Task 2: `SheetChrome` + `FormSection` primitives

**Files:**
- Create: `Nimbus/Nimbus/Components/SheetChrome.swift`
- Create: `Nimbus/Nimbus/Components/FormSection.swift`
- Create: `Nimbus/NimbusTests/SheetChromeTests.swift`
- Create: `Nimbus/NimbusTests/FormSectionTests.swift`

### Step 2.1: Write failing snapshot tests for `SheetChrome`

- [ ] Create `Nimbus/NimbusTests/SheetChromeTests.swift`:

```swift
import Testing
import SwiftUI
@testable import Nimbus

@Suite("SheetChrome")
@MainActor
struct SheetChromeTests {
    @Test func rendersTitleOnly() throws {
        let view = SheetChrome(
            title: "Add Remote",
            subtitle: nil,
            body: { Text("body content") },
            actions: { EmptyView() }
        )
        try SnapshotHelpers.assertSnapshot(
            view,
            size: CGSize(width: 500, height: 240),
            named: "SheetChrome-title-only"
        )
    }

    @Test func rendersTitleSubtitleAndActions() throws {
        let view = SheetChrome(
            title: "Edit Remote",
            subtitle: "gdrive",
            body: { Text("body content") },
            actions: {
                HStack {
                    Button("Cancel") {}
                    Button("Save") {}.buttonStyle(.borderedProminent)
                }
            }
        )
        try SnapshotHelpers.assertSnapshot(
            view,
            size: CGSize(width: 500, height: 280),
            named: "SheetChrome-full"
        )
    }
}
```

### Step 2.2: Run tests; expect failure (type not found)

```bash
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' test \
  -only-testing:NimbusTests/SheetChromeTests 2>&1 | tail -15
```

### Step 2.3: Implement `SheetChrome`

- [ ] Create `Nimbus/Nimbus/Components/SheetChrome.swift`:

```swift
import SwiftUI

/// Standard sheet layout shared across all Nimbus modal sheets.
///
/// Layout (top to bottom):
/// - Header: title (Typography.titleEmphasized) + optional subtitle (caption, textSecondary)
/// - Body: scrollable region with consistent padding (Spacing.xl)
/// - Action bar: right-aligned button row, separator above
///
/// Sheet corner radius from DesignSystem.Radius.sheet (14pt).
/// Minimum width 460pt; height grows to body content.
struct SheetChrome<Body: View, Actions: View>: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey?
    @ViewBuilder let body: () -> Body
    @ViewBuilder let actions: () -> Actions

    var bodyView: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                body()
                    .padding(DesignSystem.Spacing.xl)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            actionBar
        }
        .frame(minWidth: 460)
        .background(DesignSystem.Color.semantic.surface)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.sheet, style: .continuous))
    }

    var body: some View { bodyView }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(DesignSystem.Typography.titleEmphasized)
                .foregroundStyle(DesignSystem.Color.semantic.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DesignSystem.Spacing.xl)
        .padding(.vertical, DesignSystem.Spacing.l)
    }

    private var actionBar: some View {
        HStack {
            Spacer()
            actions()
        }
        .padding(.horizontal, DesignSystem.Spacing.xl)
        .padding(.vertical, DesignSystem.Spacing.m)
    }
}
```

### Step 2.4: Record fixtures + verify pass

```bash
cd Nimbus && xcodegen generate && cd .. && \
NIMBUS_SNAPSHOT_RECORD=1 xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus \
  -destination 'platform=macOS' test -only-testing:NimbusTests/SheetChromeTests 2>&1 | tail -10
```

Open `Nimbus/NimbusTests/Fixtures/SheetChrome-title-only.png` and `SheetChrome-full.png` and visually verify they render correctly. Then run without record flag:

```bash
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' test \
  -only-testing:NimbusTests/SheetChromeTests 2>&1 | tail -10
```

Expected: 2 tests pass.

### Step 2.5: Write failing tests for `FormSection`

- [ ] Create `Nimbus/NimbusTests/FormSectionTests.swift`:

```swift
import Testing
import SwiftUI
@testable import Nimbus

@Suite("FormSection")
@MainActor
struct FormSectionTests {
    @Test func rendersTitleAndRows() throws {
        let view = FormSection(title: "Configuration", footer: nil) {
            FormRow(label: "Name", help: nil) {
                Text("my-remote")
            }
            FormRow(label: "Type", help: "Provider type") {
                Text("s3")
            }
        }
        try SnapshotHelpers.assertSnapshot(
            view,
            size: CGSize(width: 460, height: 200),
            named: "FormSection-basic"
        )
    }

    @Test func rendersWithFooter() throws {
        let view = FormSection(
            title: "Advanced",
            footer: "These fields are optional for most users."
        ) {
            FormRow(label: "Region", help: nil) {
                Text("us-east-1")
            }
        }
        try SnapshotHelpers.assertSnapshot(
            view,
            size: CGSize(width: 460, height: 180),
            named: "FormSection-with-footer"
        )
    }
}
```

### Step 2.6: Implement `FormSection` + `FormRow`

- [ ] Create `Nimbus/Nimbus/Components/FormSection.swift`:

```swift
import SwiftUI

/// Wraps a SwiftUI section of preference-form rows with consistent typography
/// and spacing. Matches macOS System Settings preference-form style.
///
/// Use FormRow for individual labeled rows inside the section.
struct FormSection<Content: View>: View {
    let title: LocalizedStringKey?
    let footer: LocalizedStringKey?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.s) {
            if let title {
                Text(title)
                    .font(DesignSystem.Typography.captionEmphasized)
                    .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                    .textCase(.uppercase)
            }
            VStack(spacing: 0) {
                content()
            }
            .padding(DesignSystem.Spacing.m)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.card, style: .continuous)
                    .fill(DesignSystem.Color.semantic.surfaceSubtle)
            )
            if let footer {
                Text(footer)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Color.semantic.textTertiary)
            }
        }
    }
}

/// A single labeled row inside a FormSection. Label on the left, trailing content
/// (e.g. TextField, Picker, value Text) on the right.
struct FormRow<Trailing: View>: View {
    let label: LocalizedStringKey
    let help: LocalizedStringKey?
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.m) {
                Text(label)
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Color.semantic.textPrimary)
                Spacer()
                trailing()
            }
            if let help {
                Text(help)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Color.semantic.textTertiary)
            }
        }
        .padding(.vertical, DesignSystem.Spacing.xs)
    }
}
```

### Step 2.7: Record fixtures + verify pass

```bash
NIMBUS_SNAPSHOT_RECORD=1 xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus \
  -destination 'platform=macOS' test -only-testing:NimbusTests/FormSectionTests 2>&1 | tail -10
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' test \
  -only-testing:NimbusTests/FormSectionTests 2>&1 | tail -10
```

Open fixtures, verify, then re-run without record. Expected: 2 tests pass.

### Step 2.8: Commit

```bash
git add Nimbus/Nimbus/Components/SheetChrome.swift \
        Nimbus/Nimbus/Components/FormSection.swift \
        Nimbus/NimbusTests/SheetChromeTests.swift \
        Nimbus/NimbusTests/FormSectionTests.swift \
        Nimbus/NimbusTests/Fixtures \
        Nimbus/Nimbus.xcodeproj
git commit -m "feat(swiftui): add SheetChrome and FormSection primitives

- SheetChrome: header (title + subtitle) + body + action bar layout
  shared across all Nimbus modal sheets
- FormSection + FormRow: macOS System Settings preference-form style
  with consistent Typography, Spacing, Color tokens
- 4 snapshot tests (2 SheetChrome, 2 FormSection)"
```

---

## Task 3: Remotes — `RemotesView` + `RemoteRow` rebuild

**Files:**
- Replace: `Nimbus/Nimbus/Views/Remotes/RemotesView.swift`
- Replace: `Nimbus/Nimbus/Views/Remotes/RemoteRow.swift`
- Create: `Nimbus/NimbusTests/RemoteRowTests.swift`

### Step 3.1: Rebuild `RemoteRow.swift`

- [ ] Replace `Nimbus/Nimbus/Views/Remotes/RemoteRow.swift`:

```swift
import SwiftUI
import RcloneKit

enum RemoteStatus: Equatable, Sendable {
    case connected
    case authNeeded
    case error(reason: String)

    var pillText: String {
        switch self {
        case .connected: return "● Connected"
        case .authNeeded: return "⚠ Sign In"
        case .error: return "! Error"
        }
    }

    var tintColor: Color {
        switch self {
        case .connected: return DesignSystem.Color.semantic.statusOK
        case .authNeeded: return DesignSystem.Color.semantic.statusWarning
        case .error: return DesignSystem.Color.semantic.statusError
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .connected: return "Connected"
        case .authNeeded: return "Sign in required"
        case .error(let reason): return "Error: \(reason)"
        }
    }
}

/// Row representing a single remote in the Remotes list.
/// Reference: Disk Utility's volume row.
struct RemoteRow: View {
    let remote: Remote
    let status: RemoteStatus
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onBrowse: () -> Void
    let onReconnect: () -> Void

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.m) {
            Image(systemName: iconName(for: remote.type))
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .foregroundStyle(DesignSystem.Color.semantic.statusInfo)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 1) {
                Text(remote.name)
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Color.semantic.textPrimary)
                Text(remote.type)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Color.semantic.textTertiary)
            }

            Spacer()

            statusPill
                .accessibilityLabel(status.accessibilityLabel)
        }
        .padding(.vertical, DesignSystem.Spacing.xs)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onBrowse() }
        .contextMenu {
            Button("Browse") { onBrowse() }
            Button("Edit") { onEdit() }
            if case .authNeeded = status {
                Button("Reconnect") { onReconnect() }
            }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
    }

    private var statusPill: some View {
        Text(status.pillText)
            .font(DesignSystem.Typography.caption.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(
                status.tintColor.opacity(0.18),
                in: RoundedRectangle(cornerRadius: DesignSystem.Radius.pill, style: .continuous)
            )
            .foregroundStyle(status.tintColor)
    }

    private func iconName(for type: String) -> String {
        switch type {
        case "drive": return "externaldrive.connected.to.line.below"
        case "s3": return "shippingbox"
        case "dropbox": return "drop"
        case "onedrive": return "cloud"
        case "sftp", "ftp": return "server.rack"
        case "local": return "folder"
        case "crypt": return "lock.shield"
        default: return "cloud"
        }
    }
}
```

### Step 3.2: Write snapshot tests for `RemoteRow`

- [ ] Create `Nimbus/NimbusTests/RemoteRowTests.swift`:

```swift
import Testing
import SwiftUI
import RcloneKit
@testable import Nimbus

@Suite("RemoteRow")
@MainActor
struct RemoteRowTests {
    private func makeRemote(name: String = "gdrive", type: String = "drive") -> Remote {
        Remote(name: name, type: type, config: [:])
    }

    @Test func rendersConnectedStatus() throws {
        let view = RemoteRow(
            remote: makeRemote(),
            status: .connected,
            onEdit: {}, onDelete: {}, onBrowse: {}, onReconnect: {}
        )
        try SnapshotHelpers.assertSnapshot(
            view,
            size: CGSize(width: 460, height: 56),
            named: "RemoteRow-connected"
        )
    }

    @Test func rendersAuthNeededStatus() throws {
        let view = RemoteRow(
            remote: makeRemote(),
            status: .authNeeded,
            onEdit: {}, onDelete: {}, onBrowse: {}, onReconnect: {}
        )
        try SnapshotHelpers.assertSnapshot(
            view,
            size: CGSize(width: 460, height: 56),
            named: "RemoteRow-auth-needed"
        )
    }

    @Test func rendersErrorStatus() throws {
        let view = RemoteRow(
            remote: makeRemote(),
            status: .error(reason: "Server returned 500"),
            onEdit: {}, onDelete: {}, onBrowse: {}, onReconnect: {}
        )
        try SnapshotHelpers.assertSnapshot(
            view,
            size: CGSize(width: 460, height: 56),
            named: "RemoteRow-error"
        )
    }
}
```

### Step 3.3: Rebuild `RemotesView.swift`

- [ ] Replace `Nimbus/Nimbus/Views/Remotes/RemotesView.swift`:

```swift
import SwiftUI
import RcloneKit

struct RemotesView: View {
    @Environment(RcloneDaemon.self) private var daemon
    @State private var viewModel: RemotesViewModel?
    @State private var showingAddSheet = false
    @State private var showingImportSheet = false
    @State private var editingRemote: Remote?
    @State private var deletingRemote: Remote?
    @State private var searchText = ""

    let onBrowse: (String) -> Void

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel: viewModel)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Remotes")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAddSheet = true } label: {
                    Label("Add Remote", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button { showingImportSheet = true } label: {
                    Label("Import Config", systemImage: "square.and.arrow.down")
                }
            }
        }
        .searchable(text: $searchText, placement: .toolbar)
        .task {
            let vm = RemotesViewModel(client: daemon.client)
            viewModel = vm
            await vm.loadRemotes()
        }
        .sheet(isPresented: $showingAddSheet) {
            AddRemoteSheet(client: daemon.client, onDismiss: {
                Task { await viewModel?.loadRemotes() }
            })
        }
        .sheet(isPresented: $showingImportSheet) {
            ImportConfigSheet(client: daemon.client, onDismiss: {
                Task { await viewModel?.loadRemotes() }
            })
        }
        .sheet(item: $editingRemote) { remote in
            EditRemoteSheet(client: daemon.client, remote: remote, onDismiss: {
                Task { await viewModel?.loadRemotes() }
            })
        }
        .confirmationDialog(
            "Delete \(deletingRemote?.name ?? "")?",
            isPresented: Binding(
                get: { deletingRemote != nil },
                set: { if !$0 { deletingRemote = nil } }
            ),
            presenting: deletingRemote
        ) { remote in
            Button("Delete", role: .destructive) {
                Task {
                    try? await viewModel?.deleteRemote(name: remote.name)
                    deletingRemote = nil
                }
            }
            Button("Cancel", role: .cancel) { deletingRemote = nil }
        }
    }

    @ViewBuilder
    private func content(viewModel: RemotesViewModel) -> some View {
        if let error = viewModel.error {
            errorBanner(error: error, viewModel: viewModel)
        } else if viewModel.isLoading && viewModel.remotes.isEmpty {
            skeletonList
        } else if filteredRemotes(viewModel.remotes).isEmpty && viewModel.remotes.isEmpty {
            EmptyState(
                icon: "cloud.slash",
                title: "No Remotes Yet",
                message: "Add a remote to start browsing cloud storage.",
                action: .init(label: "Add Remote", perform: { showingAddSheet = true })
            )
        } else {
            List(filteredRemotes(viewModel.remotes), id: \.name) { remote in
                RemoteRow(
                    remote: remote,
                    status: .connected, // Phase 2a placeholder; richer status discovery is Phase 3
                    onEdit: { editingRemote = remote },
                    onDelete: { deletingRemote = remote },
                    onBrowse: { onBrowse(remote.name) },
                    onReconnect: { /* Phase 3 */ }
                )
            }
            .listStyle(.inset)
        }
    }

    private var skeletonList: some View {
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: DesignSystem.Spacing.m) {
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.xs)
                        .fill(DesignSystem.Color.semantic.surfaceSubtle)
                        .frame(width: 24, height: 24)
                    VStack(alignment: .leading, spacing: 4) {
                        RoundedRectangle(cornerRadius: DesignSystem.Radius.xs)
                            .fill(DesignSystem.Color.semantic.surfaceSubtle)
                            .frame(width: 120, height: 12)
                        RoundedRectangle(cornerRadius: DesignSystem.Radius.xs)
                            .fill(DesignSystem.Color.semantic.surfaceSubtle)
                            .frame(width: 60, height: 10)
                    }
                    Spacer()
                }
                .padding(.horizontal, DesignSystem.Spacing.m)
                .padding(.vertical, DesignSystem.Spacing.s)
                .redacted(reason: .placeholder)
            }
            Spacer()
        }
        .shimmering()
    }

    @ViewBuilder
    private func errorBanner(error: NimbusError, viewModel: RemotesViewModel) -> some View {
        switch error.kind {
        case .authFailed:
            EmptyState(
                icon: "key.slash",
                title: "Sign In Required",
                message: LocalizedStringKey(error.message),
                action: .init(label: "Reconnect", perform: {
                    Task { await viewModel.loadRemotes() }
                })
            )
        case .network:
            EmptyState(
                icon: "wifi.slash",
                title: "Can't Reach Cloud",
                message: LocalizedStringKey(error.message),
                action: .init(label: "Retry", perform: {
                    Task { await viewModel.loadRemotes() }
                })
            )
        case .other:
            EmptyState(
                icon: "exclamationmark.triangle",
                title: "Couldn't Load Remotes",
                message: LocalizedStringKey(error.message),
                action: .init(label: "Retry", perform: {
                    Task { await viewModel.loadRemotes() }
                })
            )
        }
    }

    private func filteredRemotes(_ remotes: [Remote]) -> [Remote] {
        guard !searchText.isEmpty else { return remotes }
        let q = searchText.lowercased()
        return remotes.filter {
            $0.name.lowercased().contains(q) || $0.type.lowercased().contains(q)
        }
    }
}
```

### Step 3.4: Verify build + capture fixtures

```bash
cd Nimbus && xcodegen generate && cd .. && \
NIMBUS_SNAPSHOT_RECORD=1 xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus \
  -destination 'platform=macOS' test -only-testing:NimbusTests/RemoteRowTests 2>&1 | tail -10
```

Open `Nimbus/NimbusTests/Fixtures/RemoteRow-*.png` (3 files), visually verify each status pill renders correctly with the right tint and pill text. Then run without record:

```bash
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' test \
  -only-testing:NimbusTests/RemoteRowTests 2>&1 | tail -10
```

Expected: 3 tests pass.

### Step 3.5: Full build sanity

```bash
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`. Existing `AddRemoteSheet`, `EditRemoteSheet`, `ImportConfigSheet` are referenced from `RemotesView` but they still compile against their old signatures — they'll be rebuilt in Tasks 4–6.

If the build fails due to signature mismatches on the sheet constructors (e.g., the sheets currently take different parameters), update the `RemotesView` `.sheet` call sites to match the current sheet constructors, with a `// TODO(Task 4-6)` comment explaining the temporary mismatch.

### Step 3.6: Commit

```bash
git add Nimbus/Nimbus/Views/Remotes/RemotesView.swift \
        Nimbus/Nimbus/Views/Remotes/RemoteRow.swift \
        Nimbus/NimbusTests/RemoteRowTests.swift \
        Nimbus/NimbusTests/Fixtures \
        Nimbus/Nimbus.xcodeproj
git commit -m "feat(swiftui): rebuild RemotesView and RemoteRow

- RemoteRow: Disk Utility-grade row with status pill (connected /
  auth-needed / error), DesignSystem tokens throughout, context menu,
  double-tap to browse, accessibility labels per state
- RemotesView: EmptyState empty-folder, skeleton + shimmer cold-load,
  NimbusError-typed error states (auth / network / other), toolbar
  with Add Remote + Import Config + search, confirmationDialog for delete
- 3 RemoteRow snapshot tests for each status state
- Status discovery is Phase 2a placeholder; live status check is Phase 3"
```

---

## Task 4: Remotes — `AddRemoteSheet` + `ConfigForm` + `ProviderPicker`

**Files:**
- Replace: `Nimbus/Nimbus/Views/Remotes/AddRemoteSheet.swift`
- Replace: `Nimbus/Nimbus/Views/Remotes/ConfigForm.swift`
- Create: `Nimbus/Nimbus/Views/Remotes/ProviderPicker.swift`

### Step 4.1: Implement `ProviderPicker.swift`

- [ ] Create `Nimbus/Nimbus/Views/Remotes/ProviderPicker.swift`:

```swift
import SwiftUI
import RcloneKit

/// Grid of provider tiles for picking a remote type in AddRemoteSheet.
/// Reference: System Settings → Add Account provider picker.
struct ProviderPicker: View {
    let providers: [Provider]
    let onPick: (Provider) -> Void
    @State private var search = ""

    private let columns = [
        GridItem(.adaptive(minimum: 96, maximum: 120), spacing: DesignSystem.Spacing.m)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.m) {
            TextField("Search providers", text: $search)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                LazyVGrid(columns: columns, spacing: DesignSystem.Spacing.m) {
                    ForEach(filtered) { provider in
                        tile(for: provider)
                    }
                }
                .padding(.vertical, DesignSystem.Spacing.s)
            }
        }
    }

    private var filtered: [Provider] {
        guard !search.isEmpty else { return providers }
        let q = search.lowercased()
        return providers.filter {
            $0.name.lowercased().contains(q) || $0.description.lowercased().contains(q)
        }
    }

    private func tile(for provider: Provider) -> some View {
        Button {
            onPick(provider)
        } label: {
            VStack(spacing: DesignSystem.Spacing.xs) {
                Image(systemName: icon(for: provider.name))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .foregroundStyle(DesignSystem.Color.semantic.statusInfo)
                Text(provider.name)
                    .font(DesignSystem.Typography.caption)
                    .lineLimit(1)
            }
            .frame(width: 96, height: 96)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.card, style: .continuous)
                    .fill(DesignSystem.Color.semantic.surfaceSubtle)
            )
        }
        .buttonStyle(.plain)
    }

    private func icon(for providerName: String) -> String {
        switch providerName.lowercased() {
        case "drive", "google drive": return "externaldrive.connected.to.line.below"
        case "s3", "amazon s3": return "shippingbox"
        case "dropbox": return "drop"
        case "onedrive": return "cloud"
        case "sftp", "ftp": return "server.rack"
        case "local": return "folder"
        case "crypt": return "lock.shield"
        case "webdav": return "globe"
        default: return "cloud"
        }
    }
}
```

### Step 4.2: Implement `ConfigForm.swift`

- [ ] Replace `Nimbus/Nimbus/Views/Remotes/ConfigForm.swift`:

```swift
import SwiftUI
import RcloneKit

/// Renders an rclone provider's config fields as a FormSection.
/// Each field becomes a FormRow with appropriate trailing input.
struct ConfigForm: View {
    let provider: Provider
    @Binding var name: String
    @Binding var values: [String: String]

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.l) {
            FormSection(title: "Remote", footer: nil) {
                FormRow(label: "Name", help: "Used to reference this remote in the Browser.") {
                    TextField("e.g. gdrive", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 240)
                }
            }
            FormSection(
                title: "Configuration",
                footer: provider.description.isEmpty ? nil : LocalizedStringKey(provider.description)
            ) {
                ForEach(provider.options ?? [], id: \.name) { option in
                    FormRow(
                        label: LocalizedStringKey(option.help ?? option.name),
                        help: option.help.map(LocalizedStringKey.init)
                    ) {
                        field(for: option)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func field(for option: ProviderOption) -> some View {
        if option.isPassword {
            SecureField("", text: binding(for: option.name))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 240)
        } else if let examples = option.examples, !examples.isEmpty {
            Picker("", selection: binding(for: option.name)) {
                Text("Choose…").tag("")
                ForEach(examples, id: \.value) { ex in
                    Text(ex.value).tag(ex.value)
                }
            }
            .frame(maxWidth: 240)
        } else {
            TextField(option.defaultValue ?? "", text: binding(for: option.name))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 240)
        }
    }

    private func binding(for key: String) -> Binding<String> {
        Binding(
            get: { values[key] ?? "" },
            set: { values[key] = $0 }
        )
    }
}
```

If `Provider` or `ProviderOption` doesn't expose `options` / `examples` / `isPassword` / `defaultValue` exactly as written, inspect the actual `Provider` model in `RcloneKit/Sources/RcloneKit/Models.swift` and adapt the field names. The structure stays the same — just map to the real property names.

### Step 4.3: Implement `AddRemoteSheet.swift`

- [ ] Replace `Nimbus/Nimbus/Views/Remotes/AddRemoteSheet.swift`:

```swift
import SwiftUI
import RcloneKit

struct AddRemoteSheet: View {
    let client: RcloneClient
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var providers: [Provider] = []
    @State private var selected: Provider?
    @State private var name = ""
    @State private var values: [String: String] = [:]
    @State private var creating = false
    @State private var error: NimbusError?

    var body: some View {
        SheetChrome(
            title: "Add Remote",
            subtitle: selected.map { LocalizedStringKey($0.name) },
            body: {
                if let selected {
                    ConfigForm(provider: selected, name: $name, values: $values)
                } else {
                    ProviderPicker(providers: providers) { provider in
                        self.selected = provider
                    }
                }
            },
            actions: {
                if selected != nil {
                    Button("Back") {
                        selected = nil
                        name = ""
                        values = [:]
                    }
                }
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                if selected != nil {
                    Button(creating ? "Adding…" : "Add Remote") {
                        Task { await create() }
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid || creating)
                }
            }
        )
        .frame(minHeight: 440)
        .task {
            do {
                providers = try await client.getProviders()
            } catch {
                self.error = NimbusError.classify(error)
            }
        }
        .alert("Couldn't add remote", isPresented: Binding(
            get: { error != nil },
            set: { if !$0 { error = nil } }
        ), presenting: error) { _ in
            Button("OK", role: .cancel) { error = nil }
        } message: { err in
            Text(err.message)
        }
    }

    private var isValid: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        // Could add per-provider required-field validation here; Phase 2a stays minimal.
        return true
    }

    private func create() async {
        creating = true
        defer { creating = false }
        guard let selected else { return }
        do {
            try await client.createRemote(
                name: name,
                type: selected.name,
                parameters: values
            )
            onDismiss()
            dismiss()
        } catch {
            self.error = NimbusError.classify(error)
        }
    }
}
```

### Step 4.4: Build and verify

```bash
cd Nimbus && xcodegen generate && cd .. && \
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`. If `client.getProviders()` or `client.createRemote(...)` have different signatures than I've assumed, find the actual signatures in `RcloneKit/Sources/RcloneKit/Remotes.swift` and adapt.

- [ ] Manually verify in the running app: open Nimbus, click + Add Remote, see the ProviderPicker grid, pick a local-type provider, see the ConfigForm appear, fill in a name and a path, click Add Remote. New remote should appear in the Remotes list. Sheet should feel HIG-grade.

### Step 4.5: Commit

```bash
git add Nimbus/Nimbus/Views/Remotes/AddRemoteSheet.swift \
        Nimbus/Nimbus/Views/Remotes/ConfigForm.swift \
        Nimbus/Nimbus/Views/Remotes/ProviderPicker.swift \
        Nimbus/Nimbus.xcodeproj
git commit -m "feat(swiftui): rebuild AddRemoteSheet with two-step ProviderPicker + ConfigForm

- ProviderPicker: 96x96 tile grid (System Settings Add Account pattern)
  with search filter and provider-type icons
- ConfigForm: FormSection wrapper over provider's option schema, fields
  routed through FormRow with help text in caption font
- AddRemoteSheet uses SheetChrome with two-step body (picker -> form)
  and conditional action bar (Cancel always; Back+Add Remote in form step)
- Error surfacing via NimbusError + .alert"
```

---

## Task 5: Remotes — `EditRemoteSheet`

**Files:**
- Replace: `Nimbus/Nimbus/Views/Remotes/EditRemoteSheet.swift`

### Step 5.1: Implement `EditRemoteSheet.swift`

- [ ] Replace `Nimbus/Nimbus/Views/Remotes/EditRemoteSheet.swift`:

```swift
import SwiftUI
import RcloneKit

struct EditRemoteSheet: View {
    let client: RcloneClient
    let remote: Remote
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var provider: Provider?
    @State private var values: [String: String] = [:]
    @State private var saving = false
    @State private var error: NimbusError?

    var body: some View {
        SheetChrome(
            title: "Edit Remote",
            subtitle: LocalizedStringKey(remote.name),
            body: {
                if let provider {
                    ConfigForm(
                        provider: provider,
                        name: .constant(remote.name),
                        values: $values
                    )
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: 200)
                }
            },
            actions: {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(saving ? "Saving…" : "Save") {
                    Task { await save() }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(saving || provider == nil)
            }
        )
        .frame(minHeight: 440)
        .task {
            do {
                let providers = try await client.getProviders()
                provider = providers.first(where: { $0.name == remote.type })
                values = remote.config
            } catch {
                self.error = NimbusError.classify(error)
            }
        }
        .alert("Couldn't save remote", isPresented: Binding(
            get: { error != nil },
            set: { if !$0 { error = nil } }
        ), presenting: error) { _ in
            Button("OK", role: .cancel) { error = nil }
        } message: { err in
            Text(err.message)
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            // rclone RC `config/update` is the right endpoint for in-place edits.
            // If RcloneKit doesn't expose updateRemote, fall through to delete+create.
            try await client.updateRemote(name: remote.name, parameters: values)
            onDismiss()
            dismiss()
        } catch {
            self.error = NimbusError.classify(error)
        }
    }
}
```

If `client.updateRemote(name:parameters:)` doesn't exist in RcloneKit, add it to `RcloneKit/Sources/RcloneKit/Remotes.swift` following the existing `createRemote` pattern but calling the rclone RC endpoint `config/update`:

```swift
public func updateRemote(name: String, parameters: [String: String]) async throws {
    var params: [String: any Sendable] = ["name": name]
    for (k, v) in parameters { params[k] = v }
    try await call("config/update", params: params)
}
```

### Step 5.2: Build + verify

```bash
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' build 2>&1 | tail -5
```

- [ ] Manually verify: open Nimbus, right-click a remote → Edit. Sheet appears with pre-filled config. Change a value, click Save. Sheet dismisses; list refreshes.

### Step 5.3: Commit

```bash
git add Nimbus/Nimbus/Views/Remotes/EditRemoteSheet.swift \
        RcloneKit/Sources/RcloneKit/Remotes.swift
git commit -m "feat(swiftui): rebuild EditRemoteSheet using SheetChrome + ConfigForm

- Pre-populates values from existing Remote.config
- Locks remote name (sheet subtitle shows it; name field is constant)
- Uses RcloneKit.updateRemote (added if absent, maps to config/update RC)
- Error surfacing via NimbusError + alert"
```

---

## Task 6: Remotes — `ImportConfigSheet` decomposition

**Files:**
- Replace: `Nimbus/Nimbus/Views/Remotes/ImportConfigSheet.swift`
- Create: `Nimbus/Nimbus/Views/Remotes/ImportPreviewList.swift`
- Create: `Nimbus/Nimbus/Views/Remotes/ImportConflictRow.swift`

The existing `ImportConfigSheet.swift` is 282 LOC. Goal: decompose into three files, each ≤120 LOC, with `SheetChrome` chrome and `FormSection`-style preview list.

### Step 6.1: Read the existing file to capture the parsing + state-machine logic

- [ ] Read `Nimbus/Nimbus/Views/Remotes/ImportConfigSheet.swift` and identify:
  - The file-picker step (probably `.fileImporter`)
  - The parsed-config representation (probably an array of `ImportedRemote` or similar)
  - The conflict detection (existing-name collisions)
  - The actual `client.createRemote` loop on confirm

Preserve all of this logic. The decomposition is structural — orchestrator owns state, child views render and forward events.

### Step 6.2: Implement `ImportPreviewList.swift`

- [ ] Create `Nimbus/Nimbus/Views/Remotes/ImportPreviewList.swift`:

```swift
import SwiftUI

/// Renders the list of parsed remotes with per-row include/exclude toggles.
/// Pure presentation; caller owns the selection set.
struct ImportPreviewList: View {
    let remotes: [ParsedRemote]
    @Binding var includedNames: Set<String>
    let conflicts: Set<String>  // names that collide with existing remotes

    var body: some View {
        FormSection(
            title: "Found \(remotes.count) remote\(remotes.count == 1 ? "" : "s")",
            footer: conflicts.isEmpty ? nil : LocalizedStringKey(
                "\(conflicts.count) name\(conflicts.count == 1 ? "" : "s") already exist. Edit the imported name in the next step to resolve."
            )
        ) {
            ForEach(remotes, id: \.name) { remote in
                row(for: remote)
                if remote.name != remotes.last?.name {
                    Divider()
                }
            }
        }
    }

    private func row(for remote: ParsedRemote) -> some View {
        HStack(spacing: DesignSystem.Spacing.m) {
            Toggle(isOn: Binding(
                get: { includedNames.contains(remote.name) },
                set: { newValue in
                    if newValue { includedNames.insert(remote.name) }
                    else { includedNames.remove(remote.name) }
                }
            )) {
                EmptyView()
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 2) {
                Text(remote.name)
                    .font(DesignSystem.Typography.body)
                Text(remote.type)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Color.semantic.textTertiary)
            }

            Spacer()

            if conflicts.contains(remote.name) {
                Label("Conflict", systemImage: "exclamationmark.triangle.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(DesignSystem.Color.semantic.statusWarning)
                    .accessibilityLabel("Name already exists")
            }
        }
        .padding(.vertical, DesignSystem.Spacing.xs)
    }
}

/// Parsed-remote shape used during import. Matches the existing ImportConfigSheet's
/// parsed representation; rename if the existing code uses a different name.
struct ParsedRemote: Hashable, Sendable {
    let name: String
    let type: String
    let parameters: [String: String]
}
```

If the existing file uses a different parsed-remote struct (e.g., named differently or with different fields), keep that struct's name and shape — rename `ParsedRemote` here to match, and remove the duplicate declaration.

### Step 6.3: Implement `ImportConflictRow.swift`

- [ ] Create `Nimbus/Nimbus/Views/Remotes/ImportConflictRow.swift`:

```swift
import SwiftUI

/// Resolves a single import-name collision by letting the user rename the
/// incoming remote. Used inside the orchestrator's conflict-resolution step.
struct ImportConflictRow: View {
    let originalName: String
    let type: String
    @Binding var newName: String

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            HStack(spacing: DesignSystem.Spacing.s) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(DesignSystem.Color.semantic.statusWarning)
                Text(originalName)
                    .font(DesignSystem.Typography.body)
                Text(type)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Color.semantic.textTertiary)
            }
            HStack(spacing: DesignSystem.Spacing.s) {
                Text("Import as:")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                TextField(originalName, text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)
            }
            .padding(.leading, DesignSystem.Spacing.l)
        }
        .padding(.vertical, DesignSystem.Spacing.xs)
    }
}
```

### Step 6.4: Rewrite `ImportConfigSheet.swift` as the orchestrator

- [ ] Replace `Nimbus/Nimbus/Views/Remotes/ImportConfigSheet.swift`:

```swift
import SwiftUI
import RcloneKit
import UniformTypeIdentifiers

private enum ImportStep {
    case pickFile
    case preview
    case resolveConflicts
}

struct ImportConfigSheet: View {
    let client: RcloneClient
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var step: ImportStep = .pickFile
    @State private var parsed: [ParsedRemote] = []
    @State private var existingNames: Set<String> = []
    @State private var includedNames: Set<String> = []
    @State private var renames: [String: String] = [:]  // original → new
    @State private var importing = false
    @State private var error: NimbusError?
    @State private var showingFilePicker = false

    var body: some View {
        SheetChrome(
            title: title,
            subtitle: nil,
            body: { stepBody },
            actions: { actionBar }
        )
        .frame(minHeight: 360)
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.init(filenameExtension: "conf") ?? .data]
        ) { result in
            handlePickedFile(result)
        }
        .task {
            await loadExisting()
        }
        .alert(
            "Import error",
            isPresented: Binding(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            ),
            presenting: error
        ) { _ in
            Button("OK", role: .cancel) { error = nil }
        } message: { err in
            Text(err.message)
        }
    }

    private var title: LocalizedStringKey {
        switch step {
        case .pickFile: return "Import Configuration"
        case .preview: return "Select Remotes to Import"
        case .resolveConflicts: return "Resolve Name Conflicts"
        }
    }

    @ViewBuilder
    private var stepBody: some View {
        switch step {
        case .pickFile:
            EmptyState(
                icon: "doc.text.magnifyingglass",
                title: "Choose an rclone.conf file",
                message: "Imported remotes are added to your current configuration.",
                action: .init(label: "Choose File…", perform: { showingFilePicker = true })
            )
        case .preview:
            if parsed.isEmpty {
                EmptyState(
                    icon: "doc.text.magnifyingglass",
                    title: "No Remotes Found",
                    message: "This file doesn't contain any rclone remotes.",
                    action: nil
                )
            } else {
                ImportPreviewList(
                    remotes: parsed,
                    includedNames: $includedNames,
                    conflicts: conflictingNames
                )
            }
        case .resolveConflicts:
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.m) {
                ForEach(Array(conflictingSelectedNames), id: \.self) { original in
                    ImportConflictRow(
                        originalName: original,
                        type: parsed.first(where: { $0.name == original })?.type ?? "",
                        newName: Binding(
                            get: { renames[original] ?? "\(original)-imported" },
                            set: { renames[original] = $0 }
                        )
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var actionBar: some View {
        Button("Cancel") { dismiss() }
            .keyboardShortcut(.cancelAction)
        switch step {
        case .pickFile:
            Button("Choose File…") { showingFilePicker = true }
                .buttonStyle(.borderedProminent)
        case .preview:
            Button("Back") { step = .pickFile }
            Button(importing ? "Importing…" : continueButtonTitle) {
                Task { await proceedFromPreview() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(includedNames.isEmpty || importing)
        case .resolveConflicts:
            Button("Back") { step = .preview }
            Button(importing ? "Importing…" : "Import") {
                Task { await performImport() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(importing)
        }
    }

    private var continueButtonTitle: String {
        conflictingSelectedNames.isEmpty ? "Import" : "Resolve Conflicts…"
    }

    private var conflictingNames: Set<String> {
        Set(parsed.map(\.name)).intersection(existingNames)
    }

    private var conflictingSelectedNames: Set<String> {
        includedNames.intersection(existingNames)
    }

    private func loadExisting() async {
        do {
            let names = try await client.listRemotes()
            existingNames = Set(names)
        } catch {
            self.error = NimbusError.classify(error)
        }
    }

    private func handlePickedFile(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            do {
                let data = try Data(contentsOf: url)
                guard let contents = String(data: data, encoding: .utf8) else {
                    throw NSError(domain: "Nimbus.Import", code: -1,
                                  userInfo: [NSLocalizedDescriptionKey: "File isn't valid UTF-8."])
                }
                parsed = parseRcloneConf(contents)
                includedNames = Set(parsed.map(\.name))
                step = .preview
            } catch {
                self.error = NimbusError.classify(error)
            }
        case .failure(let error):
            self.error = NimbusError.classify(error)
        }
    }

    private func proceedFromPreview() async {
        if conflictingSelectedNames.isEmpty {
            await performImport()
        } else {
            step = .resolveConflicts
        }
    }

    private func performImport() async {
        importing = true
        defer { importing = false }
        for parsedRemote in parsed where includedNames.contains(parsedRemote.name) {
            let targetName = renames[parsedRemote.name] ?? parsedRemote.name
            do {
                try await client.createRemote(
                    name: targetName,
                    type: parsedRemote.type,
                    parameters: parsedRemote.parameters
                )
            } catch {
                self.error = NimbusError.classify(error)
                return
            }
        }
        onDismiss()
        dismiss()
    }
}

/// Parses an rclone.conf INI-like file into ParsedRemote values.
/// Existing logic from the previous ImportConfigSheet implementation;
/// preserve verbatim by copying the parse function from the prior file.
private func parseRcloneConf(_ contents: String) -> [ParsedRemote] {
    var remotes: [ParsedRemote] = []
    var currentName: String?
    var currentType: String?
    var currentParams: [String: String] = [:]

    func flush() {
        if let name = currentName, let type = currentType {
            remotes.append(ParsedRemote(name: name, type: type, parameters: currentParams))
        }
        currentName = nil
        currentType = nil
        currentParams = [:]
    }

    for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: false) {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") { continue }
        if line.hasPrefix("[") && line.hasSuffix("]") {
            flush()
            currentName = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        } else if let eq = line.firstIndex(of: "=") {
            let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if key == "type" {
                currentType = value
            } else {
                currentParams[key] = value
            }
        }
    }
    flush()
    return remotes
}
```

If the prior `ImportConfigSheet.swift` already has a `parseRcloneConf` (or equivalent) function, copy that exact implementation in place of the simplified parser above to preserve behavior. The simplified parser handles the basic format but the prior code may have edge cases worth keeping.

### Step 6.5: Build and verify

```bash
cd Nimbus && xcodegen generate && cd .. && \
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' build 2>&1 | tail -5
```

- [ ] Manual smoke: open Nimbus, click Import Config in the Remotes toolbar, walk through the three steps: pick file → preview → (if conflicts) resolve → import. Verify final remotes appear in the list.

### Step 6.6: Commit

```bash
git add Nimbus/Nimbus/Views/Remotes/ImportConfigSheet.swift \
        Nimbus/Nimbus/Views/Remotes/ImportPreviewList.swift \
        Nimbus/Nimbus/Views/Remotes/ImportConflictRow.swift \
        Nimbus/Nimbus.xcodeproj
git commit -m "refactor(swiftui): decompose ImportConfigSheet into 3 files

- ImportConfigSheet: 3-step orchestrator (pickFile -> preview -> resolveConflicts -> import)
  Wrapped in SheetChrome with step-dependent action bar
- ImportPreviewList: per-row include/exclude toggle list with conflict markers
- ImportConflictRow: rename UI for name collisions
- Empty state when file contains no remotes (EmptyState)
- Errors surface via NimbusError + alert
- Each file <= ~150 LOC; original 282 LOC monolith split"
```

---

## Task 7: `StatusToggle` primitive

**Files:**
- Create: `Nimbus/Nimbus/Components/StatusToggle.swift`
- Create: `Nimbus/NimbusTests/StatusToggleTests.swift`

### Step 7.1: Write failing tests

- [ ] Create `Nimbus/NimbusTests/StatusToggleTests.swift`:

```swift
import Testing
import SwiftUI
@testable import Nimbus

@Suite("StatusToggle")
@MainActor
struct StatusToggleTests {
    @Test func accessibilityLabelMatchesState() {
        #expect(StatusToggleState.off.accessibilityLabel == "Off")
        #expect(StatusToggleState.on.accessibilityLabel == "On")
        #expect(StatusToggleState.mounting.accessibilityLabel == "Mounting")
        #expect(StatusToggleState.unmounting.accessibilityLabel == "Unmounting")
        #expect(StatusToggleState.error(reason: "Boom").accessibilityLabel == "Error: Boom")
    }

    @Test func equatableCompareSameState() {
        #expect(StatusToggleState.on == StatusToggleState.on)
        #expect(StatusToggleState.off == StatusToggleState.off)
        #expect(StatusToggleState.mounting == StatusToggleState.mounting)
        #expect(StatusToggleState.error(reason: "x") == StatusToggleState.error(reason: "x"))
        #expect(StatusToggleState.error(reason: "x") != StatusToggleState.error(reason: "y"))
    }

    @Test func transitioningStatesDisableInteraction() {
        #expect(StatusToggleState.mounting.isTransitioning)
        #expect(StatusToggleState.unmounting.isTransitioning)
        #expect(StatusToggleState.on.isTransitioning == false)
        #expect(StatusToggleState.off.isTransitioning == false)
        #expect(StatusToggleState.error(reason: "x").isTransitioning == false)
    }

    @Test func rendersOffState() throws {
        let view = StatusToggle(state: .off, onToggle: {})
        try SnapshotHelpers.assertSnapshot(
            view, size: CGSize(width: 60, height: 32), named: "StatusToggle-off"
        )
    }

    @Test func rendersOnState() throws {
        let view = StatusToggle(state: .on, onToggle: {})
        try SnapshotHelpers.assertSnapshot(
            view, size: CGSize(width: 60, height: 32), named: "StatusToggle-on"
        )
    }

    @Test func rendersMountingState() throws {
        let view = StatusToggle(state: .mounting, onToggle: {})
        try SnapshotHelpers.assertSnapshot(
            view, size: CGSize(width: 60, height: 32), named: "StatusToggle-mounting"
        )
    }

    @Test func rendersErrorState() throws {
        let view = StatusToggle(state: .error(reason: "Permission denied"), onToggle: {})
        try SnapshotHelpers.assertSnapshot(
            view, size: CGSize(width: 60, height: 32), named: "StatusToggle-error"
        )
    }
}
```

### Step 7.2: Run tests; expect compile failure

```bash
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' test \
  -only-testing:NimbusTests/StatusToggleTests 2>&1 | tail -10
```

### Step 7.3: Implement `StatusToggle.swift`

- [ ] Create `Nimbus/Nimbus/Components/StatusToggle.swift`:

```swift
import SwiftUI

enum StatusToggleState: Equatable, Sendable {
    case off
    case mounting
    case on
    case unmounting
    case error(reason: String)

    var accessibilityLabel: String {
        switch self {
        case .off: return "Off"
        case .mounting: return "Mounting"
        case .on: return "On"
        case .unmounting: return "Unmounting"
        case .error(let reason): return "Error: \(reason)"
        }
    }

    var isTransitioning: Bool {
        switch self {
        case .mounting, .unmounting: return true
        default: return false
        }
    }

    fileprivate var swiftUIToggleIsOn: Bool {
        switch self {
        case .on, .unmounting: return true
        case .off, .mounting, .error: return false
        }
    }
}

/// A Switch-style toggle with explicit `.mounting` / `.unmounting` / `.error`
/// transitional states. Reference: macOS System Settings → Login Items.
///
/// Caller owns the state machine. The view is pure presentation:
/// - `.off` / `.on` render the system Toggle look
/// - `.mounting` / `.unmounting` overlay a small ProgressView and disable tap
/// - `.error(reason:)` renders a red-tinted indicator with hover tooltip
struct StatusToggle: View {
    let state: StatusToggleState
    let onToggle: () -> Void

    var body: some View {
        ZStack {
            Toggle(isOn: Binding(
                get: { state.swiftUIToggleIsOn },
                set: { _ in onToggle() }
            )) {
                EmptyView()
            }
            .toggleStyle(.switch)
            .controlSize(.regular)
            .labelsHidden()
            .disabled(state.isTransitioning)
            .tint(tintColor)

            if state.isTransitioning {
                ProgressView()
                    .controlSize(.mini)
                    .padding(.horizontal, 6)
                    .background(
                        Capsule().fill(DesignSystem.Color.semantic.surface.opacity(0.85))
                    )
            }
        }
        .help(helpText)
        .accessibilityLabel(state.accessibilityLabel)
    }

    private var tintColor: Color {
        switch state {
        case .on: return DesignSystem.Color.semantic.statusInfo
        case .error: return DesignSystem.Color.semantic.statusError
        default: return DesignSystem.Color.semantic.statusInfo
        }
    }

    private var helpText: String {
        switch state {
        case .off: return "Click to mount"
        case .mounting: return "Mounting…"
        case .on: return "Click to unmount"
        case .unmounting: return "Unmounting…"
        case .error(let reason): return "Mount error: \(reason)"
        }
    }
}
```

### Step 7.4: Record fixtures + verify pass

```bash
NIMBUS_SNAPSHOT_RECORD=1 xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus \
  -destination 'platform=macOS' test -only-testing:NimbusTests/StatusToggleTests 2>&1 | tail -10
```

Open the four `StatusToggle-*.png` fixtures and verify each state renders correctly: `.off` shows a gray switch, `.on` shows a blue (statusInfo) switch, `.mounting` shows the spinner overlay, `.error` shows a red-tinted switch.

If the SwiftUI `Toggle` doesn't produce a System-Settings-grade visual for `.mounting` (e.g., the spinner positions oddly, or the tint doesn't read right), fall back to an `NSViewRepresentable` wrapper around `NSSwitch` with a sibling overlay. This is the documented Phase 2a fallback path per the spec's risks section. Note the swap in the commit message.

Then run without record:

```bash
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' test \
  -only-testing:NimbusTests/StatusToggleTests 2>&1 | tail -10
```

Expected: 7 tests pass.

### Step 7.5: Commit

```bash
git add Nimbus/Nimbus/Components/StatusToggle.swift \
        Nimbus/NimbusTests/StatusToggleTests.swift \
        Nimbus/NimbusTests/Fixtures \
        Nimbus/Nimbus.xcodeproj
git commit -m "feat(swiftui): add StatusToggle primitive with .mounting/.unmounting/.error states

- 5-state machine: .off / .mounting / .on / .unmounting / .error(reason:)
- Transitioning states (mounting/unmounting) overlay a mini ProgressView
  and disable tap
- Error state tints red with hover tooltip showing reason
- Reference: System Settings -> Login Items toggle look
- 7 tests: 3 logic + 4 snapshots

AppKit-bridge decision: SwiftUI Toggle sufficient | bridged to NSSwitch
(fill in based on the Step 7.4 visual check)."
```

---

## Task 8: Mounts — `MountsView` + `MountRow` + `MountInspector`

**Files:**
- Replace: `Nimbus/Nimbus/Views/Mounts/MountsView.swift`
- Replace: `Nimbus/Nimbus/Views/Mounts/MountRow.swift`
- Create: `Nimbus/Nimbus/Views/Mounts/MountInspector.swift`
- Create: `Nimbus/NimbusTests/MountRowTests.swift`

### Step 8.1: Implement `MountRow.swift`

- [ ] Replace `Nimbus/Nimbus/Views/Mounts/MountRow.swift`:

```swift
import SwiftUI
import RcloneKit

/// One row in the Mounts list. Layout: leading icon, name + remote subtitle,
/// trailing StatusToggle. Reference: System Settings -> Login Items row.
struct MountRow: View {
    let config: MountConfig
    let state: StatusToggleState
    let onToggle: () -> Void
    let onRevealInFinder: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.m) {
            Image(systemName: icon(for: state))
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .foregroundStyle(tint(for: state))
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 1) {
                Text(config.mountPoint.lastPathComponent.isEmpty ? "Mount" : config.mountPoint.lastPathComponent)
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Color.semantic.textPrimary)
                Text("\(config.remote)  ·  \(config.backend.displayName)")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Color.semantic.textTertiary)
            }

            Spacer()

            StatusToggle(state: state, onToggle: onToggle)
        }
        .padding(.vertical, DesignSystem.Spacing.xs)
        .contentShape(Rectangle())
        .contextMenu {
            if case .on = state {
                Button("Reveal in Finder") { onRevealInFinder() }
            }
            Button("Edit Mount") { onEdit() }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
    }

    private func icon(for state: StatusToggleState) -> String {
        switch state {
        case .on, .unmounting: return "externaldrive.fill"
        case .off, .mounting: return "externaldrive"
        case .error: return "externaldrive.badge.xmark"
        }
    }

    private func tint(for state: StatusToggleState) -> Color {
        switch state {
        case .on: return DesignSystem.Color.semantic.statusInfo
        case .error: return DesignSystem.Color.semantic.statusError
        default: return DesignSystem.Color.semantic.textTertiary
        }
    }
}
```

If `MountConfig` has different property names (`mountPoint` may be `path`, `backend` may be a different type), inspect `Nimbus/Nimbus/State/MountConfiguration.swift` and adapt.

### Step 8.2: Write `MountRow` snapshot tests

- [ ] Create `Nimbus/NimbusTests/MountRowTests.swift`:

```swift
import Testing
import SwiftUI
import Foundation
@testable import Nimbus

@Suite("MountRow")
@MainActor
struct MountRowTests {
    private func makeConfig() -> MountConfig {
        // Adapt to the actual MountConfig initializer in MountConfiguration.swift.
        // The following is a representative shape; adjust as needed.
        MountConfig(
            id: UUID(),
            remote: "gdrive",
            mountPoint: URL(fileURLWithPath: "/Users/me/Cloud/gdrive"),
            backend: .nfs,
            vfsMode: .full,
            autoMount: false
        )
    }

    @Test func rendersOffState() throws {
        let view = MountRow(
            config: makeConfig(), state: .off,
            onToggle: {}, onRevealInFinder: {}, onEdit: {}, onDelete: {}
        )
        try SnapshotHelpers.assertSnapshot(
            view, size: CGSize(width: 500, height: 56), named: "MountRow-off"
        )
    }

    @Test func rendersMountingState() throws {
        let view = MountRow(
            config: makeConfig(), state: .mounting,
            onToggle: {}, onRevealInFinder: {}, onEdit: {}, onDelete: {}
        )
        try SnapshotHelpers.assertSnapshot(
            view, size: CGSize(width: 500, height: 56), named: "MountRow-mounting"
        )
    }

    @Test func rendersOnState() throws {
        let view = MountRow(
            config: makeConfig(), state: .on,
            onToggle: {}, onRevealInFinder: {}, onEdit: {}, onDelete: {}
        )
        try SnapshotHelpers.assertSnapshot(
            view, size: CGSize(width: 500, height: 56), named: "MountRow-on"
        )
    }

    @Test func rendersErrorState() throws {
        let view = MountRow(
            config: makeConfig(), state: .error(reason: "Permission denied"),
            onToggle: {}, onRevealInFinder: {}, onEdit: {}, onDelete: {}
        )
        try SnapshotHelpers.assertSnapshot(
            view, size: CGSize(width: 500, height: 56), named: "MountRow-error"
        )
    }
}
```

### Step 8.3: Implement `MountInspector.swift`

- [ ] Create `Nimbus/Nimbus/Views/Mounts/MountInspector.swift`:

```swift
import SwiftUI

/// Expandable detail pane shown under the selected MountRow.
/// Reference: Disk Utility's volume detail pane.
struct MountInspector: View {
    let config: MountConfig
    let lastMountedAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.s) {
            detail(label: "Mount Point", value: config.mountPoint.path)
            detail(label: "Remote", value: config.remote)
            detail(label: "Backend", value: config.backend.displayName)
            detail(label: "VFS Mode", value: config.vfsMode.displayName)
            if let date = lastMountedAt {
                detail(
                    label: "Last Mounted",
                    value: DateFormatter.shortDateTime.string(from: date)
                )
            }
        }
        .padding(DesignSystem.Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.card, style: .continuous)
                .fill(DesignSystem.Color.semantic.surfaceSubtle)
        )
        .padding(.leading, DesignSystem.Spacing.l)
        .padding(.vertical, DesignSystem.Spacing.xs)
    }

    private func detail(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.m) {
            Text(label)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                .frame(width: 100, alignment: .trailing)
            Text(value)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Color.semantic.textPrimary)
                .textSelection(.enabled)
            Spacer()
        }
    }
}

private extension DateFormatter {
    static let shortDateTime: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()
}
```

If `MountConfig.backend.displayName` or `MountConfig.vfsMode.displayName` don't exist, add a small `displayName: String` computed property on each enum in `MountConfiguration.swift`.

### Step 8.4: Implement `MountsView.swift`

- [ ] Replace `Nimbus/Nimbus/Views/Mounts/MountsView.swift`:

```swift
import SwiftUI
import RcloneKit

struct MountsView: View {
    @Environment(MountManager.self) private var mountManager
    @Environment(MountConfigStore.self) private var configs
    @Environment(RcloneDaemon.self) private var daemon
    @State private var showingAddSheet = false
    @State private var editingConfig: MountConfig?
    @State private var deletingConfig: MountConfig?
    @State private var expandedID: UUID?
    @State private var error: NimbusError?

    var body: some View {
        Group {
            if configs.configs.isEmpty {
                EmptyState(
                    icon: "externaldrive",
                    title: "No Mounts Configured",
                    message: "Mount a remote to access it as a local volume.",
                    action: .init(label: "Add Mount", perform: { showingAddSheet = true })
                )
            } else {
                list
            }
        }
        .navigationTitle("Mounts")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAddSheet = true } label: {
                    Label("Add Mount", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    Task { await mountManager.refreshAll() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddMountSheet(client: daemon.client)
        }
        .sheet(item: $editingConfig) { config in
            AddMountSheet(client: daemon.client, editing: config)
        }
        .confirmationDialog(
            "Delete this mount?",
            isPresented: Binding(
                get: { deletingConfig != nil },
                set: { if !$0 { deletingConfig = nil } }
            ),
            presenting: deletingConfig
        ) { config in
            Button("Delete", role: .destructive) {
                if case .on = state(for: config) {
                    Task { try? await mountManager.unmount(config: config) }
                }
                configs.remove(id: config.id)
                deletingConfig = nil
            }
            Button("Cancel", role: .cancel) { deletingConfig = nil }
        }
        .alert(
            "Mount error",
            isPresented: Binding(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            ),
            presenting: error
        ) { _ in
            Button("OK", role: .cancel) { error = nil }
        } message: { err in
            Text(err.message)
        }
    }

    private var list: some View {
        List {
            ForEach(configs.configs) { config in
                VStack(spacing: 0) {
                    MountRow(
                        config: config,
                        state: state(for: config),
                        onToggle: { Task { await toggle(config: config) } },
                        onRevealInFinder: { revealInFinder(config: config) },
                        onEdit: { editingConfig = config },
                        onDelete: { deletingConfig = config }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(DesignSystem.Motion.smooth) {
                            expandedID = expandedID == config.id ? nil : config.id
                        }
                    }

                    if expandedID == config.id {
                        MountInspector(
                            config: config,
                            lastMountedAt: mountManager.lastMounted[config.id]
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private func state(for config: MountConfig) -> StatusToggleState {
        if let liveError = mountManager.errors[config.id] {
            return .error(reason: liveError)
        }
        if mountManager.inFlight.contains(config.id) {
            return mountManager.mountedIDs.contains(config.id) ? .unmounting : .mounting
        }
        return mountManager.mountedIDs.contains(config.id) ? .on : .off
    }

    private func toggle(config: MountConfig) async {
        do {
            if mountManager.mountedIDs.contains(config.id) {
                try await mountManager.unmount(config: config)
            } else {
                try await mountManager.mount(
                    remote: config.remote,
                    mountPoint: config.mountPoint,
                    readOnly: config.vfsMode == .readOnly
                )
            }
        } catch {
            self.error = NimbusError.classify(error)
        }
    }

    private func revealInFinder(config: MountConfig) {
        NSWorkspace.shared.activateFileViewerSelecting([config.mountPoint])
    }
}
```

If `MountManager` doesn't expose `inFlight: Set<UUID>` / `errors: [UUID: String]` / `lastMounted: [UUID: Date]` / `refreshAll()`, add them. Pattern:

```swift
@Observable
@MainActor
final class MountManager {
    private(set) var mountedIDs: Set<UUID> = []
    private(set) var inFlight: Set<UUID> = []
    private(set) var errors: [UUID: String] = [:]
    private(set) var lastMounted: [UUID: Date] = [:]

    func mount(remote: String, mountPoint: URL, readOnly: Bool) async throws {
        // Mark inFlight, do the mount, on success add to mountedIDs+lastMounted, on
        // error stash in errors. Remove from inFlight at the end either way.
    }

    func unmount(config: MountConfig) async throws { ... }

    func refreshAll() async { ... }
}
```

Preserve any existing `MountManager` API; the above additions are additive.

### Step 8.5: Record fixtures + build verification

```bash
cd Nimbus && xcodegen generate && cd .. && \
NIMBUS_SNAPSHOT_RECORD=1 xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus \
  -destination 'platform=macOS' test -only-testing:NimbusTests/MountRowTests 2>&1 | tail -10
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' test \
  -only-testing:NimbusTests/MountRowTests 2>&1 | tail -10
```

Open the 4 `MountRow-*.png` fixtures, verify each state. Expected: 4 tests pass.

### Step 8.6: Manual smoke test

- [ ] Build and run the app. Verify the Mounts screen:
  - Empty state appears when no mounts are configured.
  - Adding a mount (via AddMountSheet from Task 9 — for now use the existing sheet) populates the list.
  - Clicking a row toggles the inspector inline.
  - StatusToggle responds: tap → `.mounting` (spinner) → `.on` (filled) → Finder shows the mount.
  - Right-click menu offers Reveal in Finder when mounted.

### Step 8.7: Commit

```bash
git add Nimbus/Nimbus/Views/Mounts \
        Nimbus/Nimbus/State/MountConfiguration.swift \
        Nimbus/Nimbus/Services/MountManager.swift \
        Nimbus/NimbusTests/MountRowTests.swift \
        Nimbus/NimbusTests/Fixtures \
        Nimbus/Nimbus.xcodeproj
git commit -m "feat(swiftui): rebuild MountsView/MountRow + add MountInspector

- MountRow: System Settings Login-Items row pattern with StatusToggle
  trailing, status-tinted icon, name + remote/backend subtitle
- MountInspector: expandable Disk Utility-style detail pane shown inline
  under the selected MountRow with mount point / remote / backend /
  vfs mode / last-mounted timestamp
- MountsView: EmptyState empty-folder, NimbusError surfacing, toolbar
  with Add Mount + Refresh, confirmationDialog for destructive delete,
  reveal-in-Finder via NSWorkspace
- MountManager additions: inFlight, errors, lastMounted, refreshAll
- 4 MountRow snapshot tests per StatusToggle state"
```

---

## Task 9: Mounts — `AddMountSheet`

**Files:**
- Replace: `Nimbus/Nimbus/Views/Mounts/AddMountSheet.swift`

### Step 9.1: Implement `AddMountSheet.swift`

- [ ] Replace `Nimbus/Nimbus/Views/Mounts/AddMountSheet.swift`:

```swift
import SwiftUI
import RcloneKit

struct AddMountSheet: View {
    let client: RcloneClient
    var editing: MountConfig?

    @Environment(\.dismiss) private var dismiss
    @Environment(MountConfigStore.self) private var configs
    @State private var remote: String = ""
    @State private var remotes: [String] = []
    @State private var mountPoint: URL?
    @State private var backend: MountBackend = .nfs
    @State private var vfsMode: VFSMode = .full
    @State private var autoMount = false
    @State private var showingFolderPicker = false
    @State private var error: NimbusError?

    var body: some View {
        SheetChrome(
            title: editing == nil ? "Add Mount" : "Edit Mount",
            subtitle: nil,
            body: {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.l) {
                    FormSection(title: "Source", footer: nil) {
                        FormRow(label: "Remote", help: nil) {
                            Picker("Remote", selection: $remote) {
                                Text("Choose…").tag("")
                                ForEach(remotes, id: \.self) { Text($0).tag($0) }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 240)
                        }
                    }
                    FormSection(title: "Destination", footer: nil) {
                        FormRow(label: "Mount Point", help: "Local folder where the remote appears.") {
                            HStack {
                                Text(mountPoint?.path ?? "Not selected")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Button("Choose…") { showingFolderPicker = true }
                                    .controlSize(.small)
                            }
                            .frame(maxWidth: 320, alignment: .trailing)
                        }
                    }
                    FormSection(title: "Options", footer: nil) {
                        FormRow(label: "Backend", help: nil) {
                            Picker("Backend", selection: $backend) {
                                Text("NFS").tag(MountBackend.nfs)
                                Text("FUSE").tag(MountBackend.fuse)
                            }
                            .labelsHidden()
                            .frame(maxWidth: 160)
                        }
                        FormRow(label: "VFS Mode", help: "How the mount caches reads and writes.") {
                            Picker("VFS Mode", selection: $vfsMode) {
                                Text("Off").tag(VFSMode.off)
                                Text("Minimal").tag(VFSMode.minimal)
                                Text("Writes").tag(VFSMode.writes)
                                Text("Full").tag(VFSMode.full)
                                Text("Read-Only").tag(VFSMode.readOnly)
                            }
                            .labelsHidden()
                            .frame(maxWidth: 160)
                        }
                        FormRow(label: "Mount at Launch", help: nil) {
                            Toggle("", isOn: $autoMount)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }
                    }
                }
            },
            actions: {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(editing == nil ? "Add" : "Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
        )
        .frame(minHeight: 420)
        .fileImporter(
            isPresented: $showingFolderPicker,
            allowedContentTypes: [.folder]
        ) { result in
            switch result {
            case .success(let url): mountPoint = url
            case .failure(let err): error = NimbusError.classify(err)
            }
        }
        .task {
            do {
                remotes = try await client.listRemotes()
                if let editing {
                    remote = editing.remote
                    mountPoint = editing.mountPoint
                    backend = editing.backend
                    vfsMode = editing.vfsMode
                    autoMount = editing.autoMount
                }
            } catch {
                self.error = NimbusError.classify(error)
            }
        }
        .alert(
            "Couldn't save mount",
            isPresented: Binding(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            ),
            presenting: error
        ) { _ in
            Button("OK", role: .cancel) { error = nil }
        } message: { err in
            Text(err.message)
        }
    }

    private var isValid: Bool {
        !remote.isEmpty && mountPoint != nil
    }

    private func save() {
        guard isValid, let mp = mountPoint else { return }
        let config = MountConfig(
            id: editing?.id ?? UUID(),
            remote: remote,
            mountPoint: mp,
            backend: backend,
            vfsMode: vfsMode,
            autoMount: autoMount
        )
        if editing != nil {
            configs.update(config)
        } else {
            configs.add(config)
        }
        dismiss()
    }
}
```

If `MountConfigStore` doesn't have `add(_:)` / `update(_:)` / `remove(id:)`, add them as straightforward array mutations on `configs.configs`.

### Step 9.2: Build + manual verify

```bash
cd Nimbus && xcodegen generate && cd .. && \
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' build 2>&1 | tail -5
```

- [ ] Manually: open AddMountSheet from Mounts toolbar. Pick a remote, pick a folder, set backend + VFS, click Add. New MountRow appears.

### Step 9.3: Commit

```bash
git add Nimbus/Nimbus/Views/Mounts/AddMountSheet.swift \
        Nimbus/Nimbus/State/MountConfiguration.swift
git commit -m "feat(swiftui): rebuild AddMountSheet with SheetChrome + FormSection

- Three FormSections (Source / Destination / Options) with FormRow
  rows for Remote picker, Mount Point folder picker, Backend picker,
  VFS Mode picker, Mount-at-Launch toggle
- Doubles as Edit sheet when initialized with `editing:` config
- Folder picker uses .fileImporter with .folder content type
- Validation: requires a remote + a mount point before Save enables
- Errors surface via NimbusError + alert"
```

---

## Task 10: `ProgressMeter` primitive

**Files:**
- Create: `Nimbus/Nimbus/Components/ProgressMeter.swift`
- Create: `Nimbus/NimbusTests/ProgressMeterTests.swift`

### Step 10.1: Write failing snapshot tests

- [ ] Create `Nimbus/NimbusTests/ProgressMeterTests.swift`:

```swift
import Testing
import SwiftUI
@testable import Nimbus

@Suite("ProgressMeter")
@MainActor
struct ProgressMeterTests {
    @Test func rendersZeroProgress() throws {
        let view = ProgressMeter(progress: 0.0, speed: nil, eta: nil)
        try SnapshotHelpers.assertSnapshot(
            view, size: CGSize(width: 180, height: 24), named: "ProgressMeter-0"
        )
    }

    @Test func rendersHalfProgress() throws {
        let view = ProgressMeter(progress: 0.5, speed: 1_500_000, eta: 12)
        try SnapshotHelpers.assertSnapshot(
            view, size: CGSize(width: 240, height: 36), named: "ProgressMeter-50"
        )
    }

    @Test func rendersFullProgress() throws {
        let view = ProgressMeter(progress: 1.0, speed: nil, eta: nil)
        try SnapshotHelpers.assertSnapshot(
            view, size: CGSize(width: 180, height: 24), named: "ProgressMeter-100"
        )
    }

    @Test func clampsProgressToValidRange() {
        let belowZero = ProgressMeter(progress: -0.5, speed: nil, eta: nil)
        #expect(belowZero.clampedProgress == 0.0)
        let aboveOne = ProgressMeter(progress: 1.5, speed: nil, eta: nil)
        #expect(aboveOne.clampedProgress == 1.0)
        let inRange = ProgressMeter(progress: 0.42, speed: nil, eta: nil)
        #expect(inRange.clampedProgress == 0.42)
    }
}
```

### Step 10.2: Implement `ProgressMeter.swift`

- [ ] Create `Nimbus/Nimbus/Components/ProgressMeter.swift`:

```swift
import SwiftUI

/// Linear progress bar with optional speed + ETA caption.
/// Used in TransferRow where StatusBadge's ring is too small.
/// Color tokens match StatusBadge's downloading state for visual continuity.
struct ProgressMeter: View {
    let progress: Double      // 0.0 ... 1.0 (clamped)
    let speed: Int64?         // bytes per second
    let eta: TimeInterval?    // remaining seconds

    var clampedProgress: Double { max(0, min(1, progress)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(DesignSystem.Color.semantic.statusWarning.opacity(0.18))
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(DesignSystem.Color.semantic.statusWarning)
                        .frame(width: max(2, geo.size.width * clampedProgress))
                }
            }
            .frame(height: 6)

            if speed != nil || eta != nil {
                HStack(spacing: DesignSystem.Spacing.s) {
                    if let speed {
                        Text("\(formatBytes(speed))/s")
                    }
                    if let eta {
                        Text(formatETA(eta))
                    }
                }
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Color.semantic.textTertiary)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Progress \(Int((clampedProgress * 100).rounded())) percent")
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        var pieces: [String] = []
        if let speed { pieces.append("\(formatBytes(speed)) per second") }
        if let eta { pieces.append("\(Int(eta)) seconds remaining") }
        return pieces.joined(separator: ", ")
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func formatETA(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "\(Int(seconds))s" }
        if seconds < 3600 { return "\(Int(seconds / 60))m \(Int(seconds.truncatingRemainder(dividingBy: 60)))s" }
        return "\(Int(seconds / 3600))h \(Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60))m"
    }
}
```

### Step 10.3: Record fixtures + verify

```bash
cd Nimbus && xcodegen generate && cd .. && \
NIMBUS_SNAPSHOT_RECORD=1 xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus \
  -destination 'platform=macOS' test -only-testing:NimbusTests/ProgressMeterTests 2>&1 | tail -10
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' test \
  -only-testing:NimbusTests/ProgressMeterTests 2>&1 | tail -10
```

Open 3 `ProgressMeter-*.png` fixtures. Expected: 4 tests pass (3 snapshots + clamping logic).

### Step 10.4: Commit

```bash
git add Nimbus/Nimbus/Components/ProgressMeter.swift \
        Nimbus/NimbusTests/ProgressMeterTests.swift \
        Nimbus/NimbusTests/Fixtures \
        Nimbus/Nimbus.xcodeproj
git commit -m "feat(swiftui): add ProgressMeter primitive for transfer-row progress

- Linear progress bar in DesignSystem.Color.semantic.statusWarning (matches
  StatusBadge downloading ring for visual continuity)
- Optional speed + ETA caption underneath in caption typography
- Clamps progress to 0...1
- Accessibility label includes percentage + speed + ETA
- 4 tests (3 snapshots + clamping logic)"
```

---

## Task 11: Transfers — `TransfersView` + section grouping

**Files:**
- Replace: `Nimbus/Nimbus/Views/Transfers/TransfersView.swift`

### Step 11.1: Implement `TransfersView.swift`

- [ ] Replace `Nimbus/Nimbus/Views/Transfers/TransfersView.swift`:

```swift
import SwiftUI

enum TransferFilter: String, CaseIterable, Identifiable {
    case all
    case crossRemoteDrops
    case manualCopies
    case syncJobs

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return "All"
        case .crossRemoteDrops: return "Cross-remote Drops"
        case .manualCopies: return "Manual Copies"
        case .syncJobs: return "Sync Jobs"
        }
    }
}

struct TransfersView: View {
    @Environment(TransferStore.self) private var transferStore
    @State private var filter: TransferFilter = .all
    @State private var showRecent = true

    var body: some View {
        Group {
            if transferStore.transfers.isEmpty {
                EmptyState(
                    icon: "arrow.up.arrow.down",
                    title: "No Transfers",
                    message: "Cross-remote copies and syncs appear here.",
                    action: nil
                )
            } else {
                list
            }
        }
        .navigationTitle("Transfers")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Filter", selection: $filter) {
                        ForEach(TransferFilter.allCases) { f in
                            Text(f.displayName).tag(f)
                        }
                    }
                } label: {
                    Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button(role: .destructive) {
                    transferStore.clearCompleted()
                } label: {
                    Label("Clear Completed", systemImage: "trash")
                }
                .disabled(filteredCompleted.isEmpty)
            }
        }
    }

    private var list: some View {
        List {
            if !filteredActive.isEmpty {
                Section {
                    ForEach(filteredActive) { transfer in
                        TransferRow(transfer: transfer)
                    }
                } header: {
                    sectionHeader("Active", count: filteredActive.count)
                }
            }
            if !filteredCompleted.isEmpty {
                Section(isExpanded: $showRecent) {
                    ForEach(filteredCompleted.prefix(50)) { transfer in
                        TransferRow(transfer: transfer)
                    }
                } header: {
                    sectionHeader("Recent", count: filteredCompleted.count)
                }
            }
        }
        .listStyle(.inset)
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(DesignSystem.Typography.captionEmphasized)
                .textCase(.uppercase)
                .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
            Spacer()
            Text("\(count)")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Color.semantic.textTertiary)
        }
    }

    private var filteredActive: [Transfer] {
        applyFilter(transferStore.activeTransfers)
    }

    private var filteredCompleted: [Transfer] {
        applyFilter(transferStore.completedTransfers).sorted { lhs, rhs in
            (lhs.completedAt ?? lhs.startedAt) > (rhs.completedAt ?? rhs.startedAt)
        }
    }

    private func applyFilter(_ transfers: [Transfer]) -> [Transfer] {
        switch filter {
        case .all: return transfers
        case .crossRemoteDrops: return transfers.filter { $0.origin == .crossRemoteDrop }
        case .manualCopies: return transfers.filter { $0.origin == .manual && $0.operation == .copy }
        case .syncJobs: return transfers.filter { $0.operation == .sync }
        }
    }
}
```

### Step 11.2: Build + verify

```bash
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' build 2>&1 | tail -5
```

`TransferRow` doesn't exist yet — it's Task 12. So this build may fail. **Stage Task 12 before committing this task** by:
- Skipping the commit here and bundling Tasks 11 + 12 together, OR
- Writing a minimal placeholder TransferRow in Task 11's scope (one-liner stub) and the full version in Task 12.

Cleaner choice: bundle Tasks 11 + 12 together and commit once both compile.

### Step 11.3: Continue to Task 12 before committing

Don't commit yet. Move to Task 12.

---

## Task 12: Transfers — `TransferRow` (active / completed / failed variants)

**Files:**
- Replace: `Nimbus/Nimbus/Views/Transfers/TransferRow.swift`
- Create: `Nimbus/NimbusTests/TransferRowTests.swift`

### Step 12.1: Implement `TransferRow.swift`

- [ ] Replace `Nimbus/Nimbus/Views/Transfers/TransferRow.swift`:

```swift
import SwiftUI

struct TransferRow: View {
    let transfer: Transfer

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.m) {
            Image(systemName: iconName)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .foregroundStyle(DesignSystem.Color.semantic.textSecondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(displayName)
                    .font(DesignSystem.Typography.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitleText)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Color.semantic.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            trailing
                .frame(minWidth: 100, maxWidth: 200)
        }
        .padding(.vertical, DesignSystem.Spacing.xs)
    }

    @ViewBuilder
    private var trailing: some View {
        switch transfer.status {
        case .active:
            ProgressMeter(
                progress: transfer.progress,
                speed: nil,
                eta: nil
            )
        case .completed:
            statusPill(
                text: "● Done",
                tint: DesignSystem.Color.semantic.statusOK
            )
        case .failed(let message):
            statusPill(
                text: "! Error",
                tint: DesignSystem.Color.semantic.statusError
            )
            .help(message)
        case .cancelled:
            statusPill(
                text: "⌀ Cancelled",
                tint: DesignSystem.Color.semantic.textTertiary
            )
        }
    }

    private func statusPill(text: String, tint: Color) -> some View {
        Text(text)
            .font(DesignSystem.Typography.caption.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(
                tint.opacity(0.18),
                in: RoundedRectangle(cornerRadius: DesignSystem.Radius.pill, style: .continuous)
            )
            .foregroundStyle(tint)
    }

    private var iconName: String {
        switch transfer.operation {
        case .copy: return "doc.on.doc"
        case .sync: return "arrow.triangle.2.circlepath"
        case .move: return "arrow.right.doc.on.clipboard"
        }
    }

    private var displayName: String {
        // dstFs is typically "remote:path/to/file"; show the leaf name.
        (transfer.dstFs as NSString).lastPathComponent
    }

    private var subtitleText: String {
        "\(transfer.srcFs) → \(transfer.dstFs)"
    }
}
```

### Step 12.2: Write snapshot tests

- [ ] Create `Nimbus/NimbusTests/TransferRowTests.swift`:

```swift
import Testing
import SwiftUI
import Foundation
@testable import Nimbus

@Suite("TransferRow")
@MainActor
struct TransferRowTests {
    private func makeActive() -> Transfer {
        Transfer(
            id: 100,
            operation: .copy,
            srcFs: "gdrive:/Photos/IMG_4827.heic",
            dstFs: "s3:/Backup/IMG_4827.heic",
            startedAt: Date(),
            completedAt: nil,
            status: .active,
            origin: .crossRemoteDrop,
            nimbusUUID: UUID(),
            progress: 0.47
        )
    }

    @Test func rendersActiveWithProgress() throws {
        try SnapshotHelpers.assertSnapshot(
            TransferRow(transfer: makeActive()),
            size: CGSize(width: 560, height: 56),
            named: "TransferRow-active"
        )
    }

    @Test func rendersCompletedRow() throws {
        var t = makeActive()
        t.status = .completed
        t.completedAt = Date()
        try SnapshotHelpers.assertSnapshot(
            TransferRow(transfer: t),
            size: CGSize(width: 560, height: 56),
            named: "TransferRow-completed"
        )
    }

    @Test func rendersFailedRow() throws {
        var t = makeActive()
        t.status = .failed("Network timeout")
        t.completedAt = Date()
        try SnapshotHelpers.assertSnapshot(
            TransferRow(transfer: t),
            size: CGSize(width: 560, height: 56),
            named: "TransferRow-failed"
        )
    }
}
```

### Step 12.3: Build + record fixtures

```bash
cd Nimbus && xcodegen generate && cd .. && \
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **` (Task 11's `TransfersView` now finds `TransferRow`).

```bash
NIMBUS_SNAPSHOT_RECORD=1 xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus \
  -destination 'platform=macOS' test -only-testing:NimbusTests/TransferRowTests 2>&1 | tail -10
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' test \
  -only-testing:NimbusTests/TransferRowTests 2>&1 | tail -10
```

Open `TransferRow-active.png` / `-completed.png` / `-failed.png`. Verify:
- Active: orange progress bar at ~47% width, no status pill.
- Completed: green `● Done` pill, no progress bar.
- Failed: red `! Error` pill.

Expected: 3 tests pass.

### Step 12.4: Manual smoke test (Transfers screen end-to-end)

- [ ] Run the app. With no transfers, `EmptyState` shows. Trigger a cross-remote drag (the Phase 1 wedge) — see an Active section with a row containing ProgressMeter. Wait for completion — row moves to Recent section with Done pill. Filter menu in toolbar narrows the list. Clear Completed empties the Recent section.

### Step 12.5: Commit (Tasks 11 + 12 together)

```bash
git add Nimbus/Nimbus/Views/Transfers/TransfersView.swift \
        Nimbus/Nimbus/Views/Transfers/TransferRow.swift \
        Nimbus/NimbusTests/TransferRowTests.swift \
        Nimbus/NimbusTests/Fixtures \
        Nimbus/Nimbus.xcodeproj
git commit -m "feat(swiftui): rebuild TransfersView with section grouping + TransferRow

- TransfersView: two sections (Active grows, Recent collapsible), filter
  menu (All / Cross-remote / Manual / Sync), Clear Completed toolbar button
- TransferRow: leading op-icon, name + src→dst subtitle (middle-truncated),
  trailing ProgressMeter (active) or status pill (completed/failed/cancelled)
- EmptyState when no transfers
- 3 TransferRow snapshot tests per status variant"
```

---

## Task 13: Phase 2a exit verification + wedge smoke test

**Files:**
- Update: `docs/superpowers/specs/2026-05-15-phase2a-operational-polish-design.md` (add verification results)
- Create: `docs/superpowers/specs/<date>-phase2a-exit-gates.md` (optional, mirror Phase 1 pattern)

### Step 13.1: Full test suite green

```bash
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' test 2>&1 | \
  grep -E '(Test run|TEST SUCCEEDED|TEST FAILED|failed|passed)' | tail -5
```

Expected: ≥ 80 tests pass (55 baseline + new Phase 2a tests: 5 NimbusError + 2 SheetChrome + 2 FormSection + 3 RemoteRow + 7 StatusToggle + 4 MountRow + 4 ProgressMeter + 3 TransferRow = ~85).

### Step 13.2: Build-time lints green

```bash
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' build 2>&1 | \
  grep -E '(lint-|BUILD)' | tail -8
```

Expected: both `lint-no-system-size: OK` and `lint-package-resolved: OK` present, plus `** BUILD SUCCEEDED **`.

### Step 13.3: Manual wedge — setup-to-mount in 60 seconds

- [ ] Stop any running Nimbus instance. Launch fresh.
- [ ] Click + **Add Remote** in the Remotes toolbar.
- [ ] In `AddRemoteSheet`, pick a `local` provider from the grid.
- [ ] Fill name (e.g., `wedge-test`), and the path field (e.g., `~/Desktop`). Click **Add Remote**.
- [ ] Verify the new RemoteRow appears in the list with `● Connected` status pill.
- [ ] Click **Mounts** in the sidebar.
- [ ] Click + **Add Mount**. Pick `wedge-test`. Pick a mount point folder. Accept defaults. Click **Add**.
- [ ] Verify the new MountRow appears with the StatusToggle in `.off`.
- [ ] Click the toggle. Verify transition: `.off → .mounting` (spinner overlay visible) `→ .on` (filled blue).
- [ ] Open Finder. Verify the mount appears in the sidebar under Locations within ~2 seconds.

- [ ] Time the whole flow. Target: ≤ 60 seconds. Note any non-native moments.

### Step 13.4: VoiceOver walkthrough

- [ ] Enable VoiceOver (⌘F5). Navigate through Remotes / Mounts / Transfers screens. Every interactive element should announce a non-empty label.

### Step 13.5: Dynamic Type XXXL

- [ ] System Settings → Appearance → Text Size → XXXL. Open all three sheets (Add Remote, Edit Remote, Import Config, Add Mount). Verify no layout breaks; FormSection rows wrap gracefully.

### Step 13.6: Side-by-side HIG comparison

- [ ] Open Mounts beside System Settings → Login Items. Compare row layout, switch styling, hover affordances. Note any divergence.
- [ ] Open Transfers beside Mail (while sending an email). Compare row density, progress bar style, section grouping.
- [ ] Open AddRemoteSheet beside System Settings → Add Account. Compare sheet chrome, provider grid, form layout.

Add any must-fix divergence to the implementation log and address before claiming Phase 2a exit.

### Step 13.7: Write exit-gate doc

- [ ] Create `docs/superpowers/specs/2026-XX-XX-phase2a-exit-gates.md` (replace date with today). Use the same template as the Phase 1 exit-gate doc (`docs/superpowers/specs/2026-05-15-phase1-exit-gates.md`). Sections:
  - Objective gates (all checked ✅ or with explicit deferral)
  - Subjective gates (walkthrough, side-by-side comparisons)
  - Wedge demo result (timing, any non-native moments noted)
  - Known carry-forwards into Phase 2b / Phase 3

### Step 13.8: Final commit

```bash
git add docs/superpowers/specs
git commit -m "docs: Phase 2a exit-gate verification

All 85+ tests pass, build-time lints green, setup-to-mount wedge
verified manually at <NN> seconds. Side-by-side comparisons against
System Settings Login Items / Mail outbox / System Settings Add
Account note <none | list of divergences> divergences.

Carry-forwards into Phase 2b / Phase 3:
- <list any new ones surfaced during Phase 2a>"
```

---

## Plan self-review

**1. Spec coverage:**

| Spec section | Implementing task |
|--------------|-------------------|
| Architectural Decisions | Reflected in task scope and ordering |
| `NimbusError` foundation + ViewModel migrations | Task 1 |
| `SheetChrome` + `FormSection` primitives | Task 2 |
| Remotes — `RemotesView` + `RemoteRow` rebuild | Task 3 |
| Remotes — `AddRemoteSheet` + `ConfigForm` + `ProviderPicker` | Task 4 |
| Remotes — `EditRemoteSheet` | Task 5 |
| Remotes — `ImportConfigSheet` decomposition | Task 6 |
| `StatusToggle` primitive | Task 7 |
| Mounts — `MountsView` + `MountRow` + `MountInspector` | Task 8 |
| Mounts — `AddMountSheet` | Task 9 |
| `ProgressMeter` primitive | Task 10 |
| Transfers — `TransfersView` + section grouping | Task 11 |
| Transfers — `TransferRow` (3 variants) | Task 12 |
| Exit gates + wedge | Task 13 |

All thirteen spec implementation-order entries map to a task. No gaps.

**2. Placeholder scan:**

No "TBD" / "TODO" / "implement later" / "similar to Task N" / "add appropriate error handling" markers. Two intentional decision points are explicit (`BrowserError` typealias vs full migration in Step 1.5; SwiftUI `Toggle` vs `NSSwitch` fallback in Step 7.4). Implementation-time interpretation guidance is provided for fields that may not exactly match the existing models (`Provider.options`, `MountConfig.backend.displayName`, `MountManager.inFlight`).

**3. Type consistency:**

- `NimbusError` cases: `.authFailed` / `.network` / `.other` — consistent in Tasks 1, 3, 4, 5, 6, 8, 9.
- `StatusToggleState` cases: `.off` / `.mounting` / `.on` / `.unmounting` / `.error(reason:)` — consistent in Tasks 7, 8, 9.
- `Transfer.status` cases: `.active` / `.completed` / `.failed(_)` / `.cancelled` — consistent with existing `TransferStatus` in Tasks 11, 12.
- `SheetChrome` parameter order (title, subtitle, body, actions) — consistent in Tasks 2, 4, 5, 6, 9.
- `FormSection(title:footer:content:)` + `FormRow(label:help:trailing:)` — consistent in Tasks 2, 4, 9.

No drift.

**4. Test count consistency:**

| Task | Tests added |
|------|---|
| 1 | 5 (`NimbusError`) |
| 2 | 4 (2 SheetChrome + 2 FormSection) |
| 3 | 3 (`RemoteRow`) |
| 4 | 0 (manual smoke) |
| 5 | 0 (manual smoke) |
| 6 | 0 (decomp; covered by existing tests) |
| 7 | 7 (`StatusToggle`: 3 logic + 4 snapshots) |
| 8 | 4 (`MountRow`) |
| 9 | 0 (manual smoke) |
| 10 | 4 (`ProgressMeter`: 1 logic + 3 snapshots) |
| 11 | 0 (covered by 12's TransferRow tests + manual smoke) |
| 12 | 3 (`TransferRow`) |

Total new: 30 tests. With Phase 1 baseline 55, Phase 2a exit target ≥ 85 tests passing. Matches Step 13.1.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-15-phase2a-operational-polish.md`.
