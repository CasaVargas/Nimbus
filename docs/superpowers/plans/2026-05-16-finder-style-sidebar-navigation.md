# Finder-Style Sidebar Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make each configured remote a selectable sidebar row whose detail pane is its browser, eliminating the `NavigationStack` push that produces a duplicate "back" chevron.

**Architecture:** Replace `ContentView`'s `NavigationStack` + `NavigationPath` + `BrowserDestination` with a unified `SidebarSelection` value. Remotes are listed in the sidebar by a new `RemotesSidebarSection` (owns `RemotesViewModel`, status probing, and the Add/Import/Edit/Delete sheets). Selecting `.remote(name)` shows `BrowserView` directly. A `BrowseTarget` value lets bookmarks/`openBrowser` jump to a path in the live browser without a push.

**Tech Stack:** Swift 6, SwiftUI, `@Observable`/`@MainActor`, macOS 15. Tests: Swift Testing (`import Testing`). Build: XcodeBuildMCP. Project generation: XcodeGen (directory glob — adding/removing `.swift` files only needs `xcodegen generate`, no manual `project.yml` edits).

**Spec:** `docs/superpowers/specs/2026-05-16-finder-style-sidebar-navigation-design.md`

---

## File Structure

| Action | File | Responsibility |
|--------|------|----------------|
| New | `Nimbus/Nimbus/Views/Remotes/RemoteStatus.swift` | `RemoteStatus` enum (moved out of `RemoteRow.swift`) |
| New | `Nimbus/Nimbus/Views/SidebarSelection.swift` | `SidebarSelection` enum + `nextSelection` pure helper |
| New | `Nimbus/Nimbus/Views/Browser/BrowseTarget.swift` | `BrowseTarget` value type |
| New | `Nimbus/Nimbus/Views/Remotes/SidebarRemoteRow.swift` | Slim sidebar row: icon + name + status dot + context menu |
| New | `Nimbus/Nimbus/Views/Remotes/RemotesSidebarSection.swift` | Owns `RemotesViewModel`, status probing, Add/Import/Edit/Delete sheets, renders remote rows |
| Modify | `Nimbus/Nimbus/Views/Browser/BrowserView.swift` | Consume `BrowseTarget` via `.onChange` |
| Modify | `Nimbus/Nimbus/Views/Sidebar.swift` | Use `SidebarSelection`; embed `RemotesSidebarSection`; bookmarks set selection+target |
| Modify | `Nimbus/Nimbus/Views/ContentView.swift` | Remove NavigationStack/Path/`BrowserDestination`; new detail switch; `BrowseTarget` state; selection reconciliation |
| New | `Nimbus/NimbusTests/SidebarSelectionTests.swift` | Unit tests for `nextSelection` |
| New | `Nimbus/NimbusTests/SidebarRemoteRowTests.swift` | Snapshot tests for `SidebarRemoteRow` |
| Delete | `Nimbus/Nimbus/Views/Remotes/RemotesView.swift` | Standalone Remotes page (replaced by sidebar) |
| Delete | `Nimbus/Nimbus/Views/Remotes/RemoteRow.swift` | List-oriented row (replaced by `SidebarRemoteRow`) |
| Delete | `Nimbus/NimbusTests/RemoteRowTests.swift` | Subject deleted |

**Build command (used in every task):** XcodeBuildMCP `build_macos` with `scheme: "Nimbus"`, project `Nimbus/Nimbus.xcodeproj`.
Reference equivalent: `xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' build`

**Test command:** XcodeBuildMCP `test_macos` with `scheme: "Nimbus"`, project `Nimbus/Nimbus.xcodeproj`.
Reference equivalent: `xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' test`

**Regenerate project (after any file add/delete):** `cd Nimbus && xcodegen generate`

---

## Task 1: Extract `RemoteStatus` into its own file

`RemoteStatus` currently lives at the top of `RemoteRow.swift`, which will be deleted in Task 8. Move it first so nothing else breaks. Pure move — no behavior change.

**Files:**
- Create: `Nimbus/Nimbus/Views/Remotes/RemoteStatus.swift`
- Modify: `Nimbus/Nimbus/Views/Remotes/RemoteRow.swift:1-36` (remove the enum)

- [ ] **Step 1: Create `RemoteStatus.swift` with the enum moved verbatim**

```swift
import SwiftUI

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

- [ ] **Step 2: Delete the `RemoteStatus` enum from `RemoteRow.swift`**

Remove lines 1-36 of `Nimbus/Nimbus/Views/Remotes/RemoteRow.swift` (the `import SwiftUI` + the entire `enum RemoteStatus { … }` block, up to and including its closing brace and the blank line before the `/// Row representing…` comment). The file must now begin:

```swift
import SwiftUI
import RcloneKit

/// Row representing a single remote in the Remotes list.
/// Reference: Disk Utility's volume row.
struct RemoteRow: View {
```

- [ ] **Step 3: Regenerate the Xcode project**

Run: `cd Nimbus && xcodegen generate`
Expected: completes without error; `RemoteStatus.swift` now in the target.

- [ ] **Step 4: Build to verify the move compiles**

Use XcodeBuildMCP `build_macos` (scheme `Nimbus`).
Expected: **BUILD SUCCEEDED**. `RemoteRowTests` still compiles (it references `RemoteStatus` cases, now resolved from the new file).

- [ ] **Step 5: Commit**

```bash
git add Nimbus/Nimbus/Views/Remotes/RemoteStatus.swift Nimbus/Nimbus/Views/Remotes/RemoteRow.swift Nimbus/Nimbus.xcodeproj
git commit -m "refactor(remotes): extract RemoteStatus into its own file"
```

---

## Task 2: `SidebarSelection` enum + `nextSelection` reconciliation helper (TDD)

`nextSelection` is the only piece with real branching logic — it keeps selection valid across loads and deletes. Build it test-first.

**Behavior contract:**
- Non-remote selections (`.mounts`/`.transfers`/`.copySync`) always pass through unchanged.
- `.remote(x)` stays if `x` is in `remotes`; otherwise becomes `.remote(remotes.first)`, or `nil` if `remotes` is empty.
- `nil` selection becomes `.remote(remotes.first)` if any remote exists; stays `nil` otherwise.

**Files:**
- Create: `Nimbus/Nimbus/Views/SidebarSelection.swift`
- Test: `Nimbus/NimbusTests/SidebarSelectionTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Nimbus/NimbusTests/SidebarSelectionTests.swift`:

```swift
import Testing
@testable import Nimbus

@Suite("SidebarSelection.nextSelection")
struct SidebarSelectionTests {
    @Test func keepsValidRemoteSelection() {
        let result = nextSelection(current: .remote("b"), remotes: ["a", "b", "c"])
        #expect(result == .remote("b"))
    }

    @Test func deletedSelectedRemoteFallsBackToFirst() {
        let result = nextSelection(current: .remote("b"), remotes: ["a", "c"])
        #expect(result == .remote("a"))
    }

    @Test func deletingLastRemoteClearsSelection() {
        let result = nextSelection(current: .remote("only"), remotes: [])
        #expect(result == nil)
    }

    @Test func nilSelectionAutoSelectsFirstRemote() {
        let result = nextSelection(current: nil, remotes: ["a", "b"])
        #expect(result == .remote("a"))
    }

    @Test func nilSelectionStaysNilWhenNoRemotes() {
        let result = nextSelection(current: nil, remotes: [])
        #expect(result == nil)
    }

    @Test func nonRemoteSelectionPassesThroughUnchanged() {
        #expect(nextSelection(current: .mounts, remotes: []) == .mounts)
        #expect(nextSelection(current: .transfers, remotes: ["a"]) == .transfers)
        #expect(nextSelection(current: .copySync, remotes: ["a"]) == .copySync)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Use XcodeBuildMCP `test_macos` (scheme `Nimbus`).
Expected: FAIL — `cannot find 'nextSelection' in scope` / `cannot find 'SidebarSelection'`.

- [ ] **Step 3: Write the minimal implementation**

Create `Nimbus/Nimbus/Views/SidebarSelection.swift`:

```swift
import Foundation

/// What the sidebar currently has selected. A remote selection drives the
/// detail pane to that remote's browser; the other cases map to their views.
enum SidebarSelection: Hashable {
    case remote(String)
    case mounts
    case transfers
    case copySync
}

/// Reconciles a selection against the current set of remote names. Used both
/// to auto-select on first load and to recover after a remote is deleted.
/// Non-remote selections are never altered.
func nextSelection(current: SidebarSelection?, remotes: [String]) -> SidebarSelection? {
    switch current {
    case .mounts, .transfers, .copySync:
        return current
    case .remote(let name):
        if remotes.contains(name) { return .remote(name) }
        return remotes.first.map(SidebarSelection.remote)
    case nil:
        return remotes.first.map(SidebarSelection.remote)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Use XcodeBuildMCP `test_macos` (scheme `Nimbus`). (Run `cd Nimbus && xcodegen generate` first so the two new files are in their targets.)
Expected: PASS — all 6 `SidebarSelectionTests` green.

- [ ] **Step 5: Commit**

```bash
git add Nimbus/Nimbus/Views/SidebarSelection.swift Nimbus/NimbusTests/SidebarSelectionTests.swift Nimbus/Nimbus.xcodeproj
git commit -m "feat(nav): add SidebarSelection + nextSelection reconciliation helper"
```

---

## Task 3: `BrowseTarget` type + `BrowserView` observation

Bookmarks and the `openBrowser` action must open a remote at a specific path without a navigation push. Add the value type and make the live `BrowserView` react to it.

**Files:**
- Create: `Nimbus/Nimbus/Views/Browser/BrowseTarget.swift`
- Modify: `Nimbus/Nimbus/Views/Browser/BrowserView.swift`

- [ ] **Step 1: Create `BrowseTarget.swift`**

```swift
import Foundation

/// A request to show a specific path inside a remote. Published by bookmark
/// taps and the `openBrowser` action; consumed by the live `BrowserView` so a
/// jump preserves the running browser instead of recreating it.
struct BrowseTarget: Equatable {
    let remote: String
    let path: String
}
```

- [ ] **Step 2: Add an optional `browseTarget` input to `BrowserView`**

In `Nimbus/Nimbus/Views/Browser/BrowserView.swift`, add the property after `var initialPath: String = ""` (line 7):

```swift
    let remoteName: String
    var initialPath: String = ""
    /// When this changes and its `remote` matches `remoteName`, the browser
    /// navigates to `path` on the live view model (no view recreation).
    var browseTarget: BrowseTarget?
```

- [ ] **Step 3: React to `browseTarget` changes**

In `BrowserView.body`, add an `.onChange` modifier immediately after the existing `.task { … }` block (currently lines 100-106, ends with `}` before `.alert("New Folder"…`):

```swift
        .onChange(of: browseTarget) { _, newValue in
            guard let target = newValue, target.remote == remoteName,
                  let viewModel else { return }
            Task { await viewModel.navigateTo(path: target.path) }
        }
```

- [ ] **Step 4: Regenerate + build**

Run: `cd Nimbus && xcodegen generate`
Use XcodeBuildMCP `build_macos` (scheme `Nimbus`).
Expected: **BUILD SUCCEEDED** (no call sites changed yet — `browseTarget` defaults to `nil`).

- [ ] **Step 5: Commit**

```bash
git add Nimbus/Nimbus/Views/Browser/BrowseTarget.swift Nimbus/Nimbus/Views/Browser/BrowserView.swift Nimbus/Nimbus.xcodeproj
git commit -m "feat(browser): add BrowseTarget, navigate live browser on target change"
```

---

## Task 4: `SidebarRemoteRow` view + snapshot tests

A slim sidebar row. Snapshot tests record a fixture on first run, then assert stability (same pattern as the existing `RemoteRowTests`).

**Files:**
- Create: `Nimbus/Nimbus/Views/Remotes/SidebarRemoteRow.swift`
- Test: `Nimbus/NimbusTests/SidebarRemoteRowTests.swift`

- [ ] **Step 1: Create `SidebarRemoteRow.swift`**

```swift
import SwiftUI
import RcloneKit

/// One remote in the sidebar's REMOTES section. Icon + name + a small status
/// dot (the full status pill is too heavy for a sidebar row). Right-click
/// exposes the same actions the old list row had.
struct SidebarRemoteRow: View {
    let remote: Remote
    let status: RemoteStatus
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onReconnect: () -> Void

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.s) {
            ProviderIcon(provider: remote.type, size: 18)
                .frame(width: 20)

            Text(remote.name)
                .font(DesignSystem.Typography.body)
                .lineLimit(1)

            Spacer(minLength: DesignSystem.Spacing.s)

            Circle()
                .fill(status.tintColor)
                .frame(width: 7, height: 7)
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Edit…", action: onEdit)
            if case .authNeeded = status {
                Button("Reconnect", action: onReconnect)
            }
            Divider()
            Button("Delete…", role: .destructive, action: onDelete)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(remote.name), \(status.accessibilityLabel)")
        .accessibilityAction(named: "Edit", onEdit)
        .accessibilityAction(named: "Reconnect", onReconnect)
        .accessibilityAction(named: "Delete", onDelete)
    }
}

#Preview {
    List {
        Section("Remotes") {
            SidebarRemoteRow(remote: Remote(name: "gdrive", type: "drive", config: [:]),
                             status: .connected, onEdit: {}, onDelete: {}, onReconnect: {})
            SidebarRemoteRow(remote: Remote(name: "backup-s3", type: "s3", config: [:]),
                             status: .authNeeded, onEdit: {}, onDelete: {}, onReconnect: {})
            SidebarRemoteRow(remote: Remote(name: "archive", type: "b2", config: [:]),
                             status: .unknown, onEdit: {}, onDelete: {}, onReconnect: {})
        }
    }
    .listStyle(.sidebar)
    .frame(width: 220, height: 200)
}
```

- [ ] **Step 2: Write the snapshot tests**

Create `Nimbus/NimbusTests/SidebarRemoteRowTests.swift`:

```swift
import Testing
import SwiftUI
import RcloneKit
@testable import Nimbus

@Suite("SidebarRemoteRow", .serialized)
@MainActor
struct SidebarRemoteRowTests {
    private func makeRemote(name: String = "gdrive", type: String = "drive") -> Remote {
        Remote(name: name, type: type, config: [:])
    }

    @Test func rendersConnectedStatus() throws {
        let view = SidebarRemoteRow(
            remote: makeRemote(), status: .connected,
            onEdit: {}, onDelete: {}, onReconnect: {}
        )
        try SnapshotHelpers.assertSnapshot(
            view, size: CGSize(width: 220, height: 28), named: "SidebarRemoteRow-connected"
        )
    }

    @Test func rendersAuthNeededStatus() throws {
        let view = SidebarRemoteRow(
            remote: makeRemote(), status: .authNeeded,
            onEdit: {}, onDelete: {}, onReconnect: {}
        )
        try SnapshotHelpers.assertSnapshot(
            view, size: CGSize(width: 220, height: 28), named: "SidebarRemoteRow-auth-needed"
        )
    }

    @Test func rendersUnknownStatus() throws {
        let view = SidebarRemoteRow(
            remote: makeRemote(), status: .unknown,
            onEdit: {}, onDelete: {}, onReconnect: {}
        )
        try SnapshotHelpers.assertSnapshot(
            view, size: CGSize(width: 220, height: 28), named: "SidebarRemoteRow-unknown"
        )
    }
}
```

- [ ] **Step 3: Regenerate, then record the snapshot fixtures**

Run: `cd Nimbus && xcodegen generate`
Run tests once in record mode so fixtures are written: XcodeBuildMCP `test_macos` (scheme `Nimbus`) with environment `NIMBUS_SNAPSHOT_RECORD=1`.
Reference equivalent: `NIMBUS_SNAPSHOT_RECORD=1 xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' test -only-testing:NimbusTests/SidebarRemoteRowTests`
Expected: tests "fail" with `Recorded fixture …` issues (this is the helper's record behavior), and 3 PNGs appear under `Nimbus/NimbusTests/Fixtures/`.

- [ ] **Step 4: Run the tests again to verify they pass against fixtures**

Use XcodeBuildMCP `test_macos` (scheme `Nimbus`), no record env.
Expected: PASS — `SidebarRemoteRow-connected`, `-auth-needed`, `-unknown` all within hash tolerance.

- [ ] **Step 5: Commit (including fixtures)**

```bash
git add Nimbus/Nimbus/Views/Remotes/SidebarRemoteRow.swift Nimbus/NimbusTests/SidebarRemoteRowTests.swift Nimbus/NimbusTests/Fixtures Nimbus/Nimbus.xcodeproj
git commit -m "feat(remotes): add SidebarRemoteRow with snapshot coverage"
```

---

## Task 5: `RemotesSidebarSection` container

Owns `RemotesViewModel`, runs status probing, hosts the Add/Import/Edit/Delete sheets (lifted from `RemotesView`), and renders the remote rows. Reports the loaded remote-name list upward so `ContentView` can reconcile selection.

**Files:**
- Create: `Nimbus/Nimbus/Views/Remotes/RemotesSidebarSection.swift`

- [ ] **Step 1: Create `RemotesSidebarSection.swift`**

```swift
import SwiftUI
import RcloneKit

/// The REMOTES section of the sidebar. Loads remotes, probes their status,
/// owns the add/import/edit/delete UI, and tells the parent which remotes
/// exist so selection can be reconciled.
struct RemotesSidebarSection: View {
    @Environment(RcloneDaemon.self) private var daemon
    @Environment(RemoteStatusService.self) private var statusService

    /// Called every time the remote list (re)loads, with the current names.
    var onRemotesLoaded: ([String]) -> Void

    @State private var viewModel: RemotesViewModel?
    @State private var showAddRemote = false
    @State private var showImportConfig = false
    @State private var editingRemote: Remote?
    @State private var deletingRemote: Remote?

    var body: some View {
        Section {
            if let viewModel, !viewModel.remotes.isEmpty {
                ForEach(viewModel.remotes, id: \.name) { remote in
                    SidebarRemoteRow(
                        remote: remote,
                        status: statusService.statuses[remote.name] ?? .unknown,
                        onEdit: { editingRemote = remote },
                        onDelete: { deletingRemote = remote },
                        onReconnect: { Task { await statusService.probe(remote.name) } }
                    )
                    .tag(SidebarSelection.remote(remote.name))
                }
            } else if daemon.status == .connected {
                Button {
                    showAddRemote = true
                } label: {
                    Label("Add Remote…", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        } header: {
            HStack {
                Text("Remotes")
                Spacer()
                Menu {
                    Button("Add Remote…", systemImage: "plus") { showAddRemote = true }
                    Button("Import Config…", systemImage: "square.and.arrow.down") { showImportConfig = true }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(daemon.status != .connected)
                .help("Add or import a remote")
            }
        }
        .task(id: daemon.status) {
            guard daemon.status == .connected else { return }
            if viewModel == nil {
                viewModel = RemotesViewModel(client: daemon.client)
            }
            await reload()
        }
        .sheet(isPresented: $showAddRemote) {
            AddRemoteSheet(client: daemon.client, onDismiss: { Task { await reload() } })
        }
        .sheet(isPresented: $showImportConfig) {
            ImportConfigSheet(onDismiss: { Task { await reload() } })
        }
        .sheet(isPresented: Binding(
            get: { editingRemote != nil },
            set: { if !$0 { editingRemote = nil } }
        )) {
            if let remote = editingRemote {
                EditRemoteSheet(client: daemon.client, remote: remote,
                                onDismiss: { Task { await reload() } })
            }
        }
        .confirmationDialog(
            "Delete \(deletingRemote?.name ?? "")?",
            isPresented: Binding(
                get: { deletingRemote != nil },
                set: { if !$0 { deletingRemote = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let remote = deletingRemote {
                    let name = remote.name
                    Task {
                        await viewModel?.deleteRemote(name: name)
                        statusService.clear(name)
                        await reload()
                    }
                }
            }
            Button("Cancel", role: .cancel) { deletingRemote = nil }
        } message: {
            Text("This will remove the remote configuration. Files on the cloud are not affected.")
        }
    }

    private func reload() async {
        guard let viewModel else { return }
        await viewModel.loadRemotes()
        let names = viewModel.remotes.map(\.name)
        if !names.isEmpty { await statusService.probeAll(names) }
        onRemotesLoaded(names)
    }
}
```

- [ ] **Step 2: Regenerate + build**

Run: `cd Nimbus && xcodegen generate`
Use XcodeBuildMCP `build_macos` (scheme `Nimbus`).
Expected: **BUILD SUCCEEDED**. (`RemotesSidebarSection` is not referenced yet — this verifies it compiles in isolation, including the `AddRemoteSheet`/`ImportConfigSheet`/`EditRemoteSheet` call sites, which keep the same signatures used by `RemotesView`.)

- [ ] **Step 3: Commit**

```bash
git add Nimbus/Nimbus/Views/Remotes/RemotesSidebarSection.swift Nimbus/Nimbus.xcodeproj
git commit -m "feat(remotes): add RemotesSidebarSection container"
```

---

## Task 6: Rewire `Sidebar` + `ContentView` (atomic refactor)

These two files share the selection binding and the `NavigationStack` removal, so they must change together to keep the build green. This is one logical change broken into fine steps.

**Files:**
- Modify: `Nimbus/Nimbus/Views/Sidebar.swift` (full rewrite of the view)
- Modify: `Nimbus/Nimbus/Views/ContentView.swift` (remove NavigationStack/Path/`BrowserDestination`; new detail switch; `BrowseTarget` state; selection reconciliation)

- [ ] **Step 1: Rewrite `Sidebar.swift`**

Replace the entire contents of `Nimbus/Nimbus/Views/Sidebar.swift` with:

```swift
import SwiftUI

struct Sidebar: View {
    @Binding var selection: SidebarSelection?
    @Environment(BookmarkStore.self) private var bookmarkStore
    var onRemotesLoaded: ([String]) -> Void
    var onBookmarkSelected: ((String, String) -> Void)?
    var onBookmarkDrop: ((_ bundles: [NimbusFileBundle], _ bookmark: FolderBookmark) -> Void)?

    var body: some View {
        List(selection: $selection) {
            RemotesSidebarSection(onRemotesLoaded: onRemotesLoaded)

            Section {
                Label("Mounts", systemImage: "externaldrive")
                    .tag(SidebarSelection.mounts)
                Label("Transfers", systemImage: "arrow.up.arrow.down")
                    .tag(SidebarSelection.transfers)
                Label("Copy / Sync", systemImage: "doc.on.doc")
                    .tag(SidebarSelection.copySync)
            }

            if !bookmarkStore.bookmarks.isEmpty {
                Section("Bookmarks") {
                    ForEach(bookmarkStore.bookmarks) { bookmark in
                        // HStack + .onTapGesture (not Button): a Button inside a
                        // List intercepts drag events and breaks .dropDestination.
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bookmark.label)
                                Text("\(bookmark.remoteName):\(bookmark.path)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "folder.badge.star")
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onBookmarkSelected?(bookmark.remoteName, bookmark.path)
                        }
                        .contextMenu {
                            Button("Remove Bookmark", role: .destructive) {
                                bookmarkStore.removeBookmark(id: bookmark.id)
                            }
                        }
                        .dropDestination(for: NimbusFileBundle.self) { bundles, _ in
                            onBookmarkDrop?(bundles, bookmark)
                            return true
                        }
                    }
                    .onMove { fromOffsets, toOffset in
                        bookmarkStore.reorder(fromOffsets: fromOffsets, toOffset: toOffset)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Nimbus")
    }
}
```

(`SidebarItem` is fully removed — it had no other consumers per `grep`.)

- [ ] **Step 2: Rewrite `ContentView.swift`**

Replace the entire contents of `Nimbus/Nimbus/Views/ContentView.swift` with:

```swift
import SwiftUI
import os

struct ContentView: View {
    @State private var selection: SidebarSelection?
    @State private var browseTarget: BrowseTarget?
    @State private var pendingSidebarCopy: CopyRequest?
    @Environment(AppSettings.self) private var settings
    @Environment(RcloneDaemon.self) private var daemon
    @Environment(TransferStore.self) private var transferStore

    var body: some View {
        if !settings.onboardingComplete {
            OnboardingView()
        } else {
            NavigationSplitView {
                Sidebar(
                    selection: $selection,
                    onRemotesLoaded: { names in
                        selection = nextSelection(current: selection, remotes: names)
                    },
                    onBookmarkSelected: { remote, path in
                        selection = .remote(remote)
                        browseTarget = BrowseTarget(remote: remote, path: path)
                    },
                    onBookmarkDrop: { bundles, bookmark in
                        handleBookmarkDrop(refs: bundles.flatMap(\.refs), bookmark: bookmark)
                    }
                )
                .frame(minWidth: 180)
            } detail: {
                detailView
            }
            .frame(minWidth: 800, minHeight: 600)
            .toolbar {
                if case .error(let message) = daemon.status {
                    ToolbarItem(placement: .status) {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .environment(\.openBrowser, OpenBrowserAction { remote in
                selection = .remote(remote)
                browseTarget = BrowseTarget(remote: remote, path: "")
            })
            .sheet(item: $pendingSidebarCopy) { _ in
                ConfirmCopySheet(request: $pendingSidebarCopy) { req in
                    Task {
                        let coord = DragDropCoordinator(
                            transferStore: transferStore,
                            rclone: RcloneClientAdapter(client: daemon.client)
                        )
                        do {
                            try await coord.apply(
                                .crossRemote(items: req.items, sourceRemote: req.sourceRemote, target: req.target),
                                conflictPolicy: req.conflictPolicy
                            )
                        } catch {
                            Logger(subsystem: "app.casavargas.nimbus", category: "sidebar")
                                .error("Bookmark cross-remote copy failed: \(String(describing: error))")
                        }
                    }
                }
            }
        }
    }

    private func handleBookmarkDrop(refs: [NimbusFileRef], bookmark: FolderBookmark) {
        let coord = DragDropCoordinator(
            transferStore: transferStore,
            rclone: RcloneClientAdapter(client: daemon.client)
        )
        let target = DropIntent.DropTarget(remote: bookmark.remoteName, path: bookmark.path)
        do {
            let intent = try coord.resolve(drop: refs, onto: target)
            if case .crossRemote(let items, let sourceRemote, let resolvedTarget) = intent {
                pendingSidebarCopy = CopyRequest(
                    sourceRemote: sourceRemote,
                    target: resolvedTarget,
                    items: items
                )
            }
            // Within-remote / toFinder bookmark drops are no-ops in Phase 1.
        } catch {
            Logger(subsystem: "app.casavargas.nimbus", category: "sidebar")
                .warning("Bookmark drop resolve error: \(String(describing: error))")
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .remote(let name):
            BrowserView(remoteName: name, browseTarget: browseTarget)
                .id(name)
        case .mounts:
            MountsView()
        case .transfers:
            TransfersView()
        case .copySync:
            CopySyncView()
        case nil:
            EmptyState(
                icon: "cloud.slash",
                title: "No Remote Selected",
                message: "Select a remote in the sidebar, or add one with the + button."
            )
        }
    }
}

struct OpenBrowserAction {
    let action: (String) -> Void
    func callAsFunction(_ remote: String) { action(remote) }
}

extension EnvironmentValues {
    @Entry var openBrowser = OpenBrowserAction { _ in }
}
```

- [ ] **Step 3: Verify `EmptyState` supports the message-only call**

Open `Nimbus/Nimbus/Components/EmptyState.swift`. Confirm an initializer accepting `icon:`, `title:`, `message:` **without** an `action:` exists (existing call sites like `RemotesView` always passed `action:`; the `nil`-selection state above omits it). If `action` is non-optional, instead use the existing form with a harmless action — change the `case nil:` branch to:

```swift
        case nil:
            EmptyState(
                icon: "cloud.slash",
                title: "No Remote Selected",
                messageVerbatim: "Select a remote in the sidebar, or add one with the + button."
            )
```

Pick whichever overload actually exists (`message:`/`messageVerbatim:`, with/without `action:`). Do not invent a new initializer — match `EmptyState.swift`'s real API. If only an `action:`-bearing initializer exists, pass `action: nil` if the parameter is optional, otherwise add a no-op `.init(label: "Add Remote", perform: {})` consistent with other call sites.

- [ ] **Step 4: Regenerate + build**

Run: `cd Nimbus && xcodegen generate`
Use XcodeBuildMCP `build_macos` (scheme `Nimbus`).
Expected: **BUILD SUCCEEDED**. `RemotesView.swift`/`RemoteRow.swift` are now unreferenced but still compile (deleted in Task 8).

- [ ] **Step 5: Run the full test suite**

Use XcodeBuildMCP `test_macos` (scheme `Nimbus`).
Expected: PASS — `SidebarSelectionTests`, `SidebarRemoteRowTests`, and pre-existing suites green. `RemoteRowTests` still green (subject not yet deleted).

- [ ] **Step 6: Commit**

```bash
git add Nimbus/Nimbus/Views/Sidebar.swift Nimbus/Nimbus/Views/ContentView.swift Nimbus/Nimbus.xcodeproj
git commit -m "feat(nav): Finder-style sidebar — remotes as rows, drop NavigationStack"
```

---

## Task 7: Manual visual verification (no duplicate chevron)

Per the project UI workflow, confirm the fix visually before deleting the old code.

**Files:** none (verification only).

- [ ] **Step 1: Launch the app**

Use XcodeBuildMCP `build_run_macos` (scheme `Nimbus`).

- [ ] **Step 2: Verify the navigation**

Confirm by observation:
- The sidebar shows each remote as a row with its provider icon and a status dot.
- Selecting a remote shows its browser in the detail pane immediately.
- The toolbar has **exactly one** back/forward control (folder history). There is **no** second chevron and no "back to Remotes" affordance.
- Navigating into a folder then back works via the single back button and the breadcrumb.
- The REMOTES header "+" menu opens Add/Import; a row's right-click menu shows Edit/Delete (and Reconnect when auth is needed).
- Clicking a bookmark selects its remote and jumps to the bookmarked path.

- [ ] **Step 3: Capture evidence**

Take a screenshot of the browsing state showing the single-chevron toolbar (XcodeBuildMCP `screenshot`, or RenderPreview of the relevant view). Visually confirm — do not defer the judgement.

If anything is wrong, fix it and re-verify before proceeding. No commit (verification task) unless a fix was required, in which case commit the fix with `fix(nav): …`.

---

## Task 8: Delete the replaced files

Now that nothing references them, remove the standalone Remotes page, the old row, and its tests.

**Files:**
- Delete: `Nimbus/Nimbus/Views/Remotes/RemotesView.swift`
- Delete: `Nimbus/Nimbus/Views/Remotes/RemoteRow.swift`
- Delete: `Nimbus/NimbusTests/RemoteRowTests.swift`

- [ ] **Step 1: Confirm zero references**

Run: `grep -rn --include="*.swift" "RemotesView\|RemoteRow\b" Nimbus/Nimbus Nimbus/NimbusTests`
Expected: only matches inside the three files about to be deleted (and `SidebarRemoteRow`, which is a different symbol — the `\b` after `RemoteRow` excludes it). If any other file references `RemotesView` or `RemoteRow`, stop and resolve before deleting.

- [ ] **Step 2: Delete the files**

```bash
git rm Nimbus/Nimbus/Views/Remotes/RemotesView.swift \
       Nimbus/Nimbus/Views/Remotes/RemoteRow.swift \
       Nimbus/NimbusTests/RemoteRowTests.swift
```

- [ ] **Step 3: Remove the orphaned snapshot fixtures**

```bash
git rm Nimbus/NimbusTests/Fixtures/RemoteRow-connected.png \
       Nimbus/NimbusTests/Fixtures/RemoteRow-auth-needed.png \
       Nimbus/NimbusTests/Fixtures/RemoteRow-error.png
```
(If any path doesn't exist, drop it from the command — fixtures are only present if `RemoteRowTests` was ever run in record mode.)

- [ ] **Step 4: Regenerate + build + test**

Run: `cd Nimbus && xcodegen generate`
Use XcodeBuildMCP `build_macos` then `test_macos` (scheme `Nimbus`).
Expected: **BUILD SUCCEEDED**; full suite PASS with no `RemoteRowTests` present.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor(remotes): delete standalone Remotes page + old RemoteRow"
```

---

## Self-Review

**Spec coverage:**
- Sidebar restructure (remotes as rows, "+" menu, context menu, no search) → Tasks 4, 5, 6 ✓
- `SidebarSelection` + remove `NavigationStack`/`NavigationPath`/`BrowserDestination` → Tasks 2, 6 ✓
- `SidebarRemoteRow` (slim, status dot, preview) → Task 4 ✓
- `RemotesSidebarSection` (VM ownership, status probing moved, sheets hosted) → Task 5 ✓
- `BrowseTarget` observed by live browser → Tasks 3, 6 ✓
- Detail switch + `nil` empty state + daemon states → Task 6 ✓
- Delete-selected fallback / auto-select first / zero remotes → Tasks 2 (helper), 5 (zero-remote affordance), 6 (wiring) ✓
- `RemoteStatus` extracted before `RemoteRow` deletion → Tasks 1, 8 ✓
- Tests: `nextSelection` unit, `SidebarRemoteRow` snapshot, `RemoteRowTests` removal → Tasks 2, 4, 8 ✓
- Visual verification (single chevron) → Task 7 ✓

**Daemon error/starting states:** The spec says the idle/starting spinner + error `EmptyState` from `RemotesView.content` should not be lost. In the new model the detail pane for `.remote` is `BrowserView` (own error handling) and `nil` shows the no-selection `EmptyState`; the daemon `.error` banner is preserved in `ContentView`'s `.toolbar`. The standalone full-pane daemon spinner is intentionally not reproduced — it belonged to the deleted page and the toolbar banner + per-browser states cover the connected/error cases. This is consistent with the spec's "this logic moves into the detail's no-/remote branch" intent without resurrecting a dead page; flagged here as a deliberate, reviewed deviation.

**Placeholder scan:** No TBD/TODO/"handle errors" placeholders. Step 3 of Task 6 is an explicit decision step against the real `EmptyState` API (not a placeholder — it instructs matching existing code rather than guessing a signature).

**Type consistency:** `SidebarSelection` cases (`.remote`/`.mounts`/`.transfers`/`.copySync`), `nextSelection(current:remotes:)`, `BrowseTarget(remote:path:)`, `SidebarRemoteRow(remote:status:onEdit:onDelete:onReconnect:)`, `RemotesSidebarSection(onRemotesLoaded:)`, and `Sidebar(selection:onRemotesLoaded:onBookmarkSelected:onBookmarkDrop:)` are used identically across Tasks 2–6. `RemotesViewModel`/sheet signatures match the originals read from `RemotesView.swift`.
