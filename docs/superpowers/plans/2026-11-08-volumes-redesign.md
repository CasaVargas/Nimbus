# Volumes Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Library/Finder/Transfers sidebar layout with one Disk-Utility-style pane per remote (header, gauge, verbs, Files/Transfers/Finder/Settings tabs, transfer drawer, inspector).

**Architecture:** `VolumeView` becomes the detail view for `.remote(name)` and composes the existing `BrowserView`, `TransfersView`, and `MountsView` as tabs by giving those views an optional `remoteFilter`. Quota comes from `RemoteStatusService` via `operations/about`. No new persistence beyond `AppSettings.inspectorVisible`.

**Tech Stack:** Swift 6, SwiftUI (macOS 15), RcloneKit, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-11-08-volumes-redesign-design.md`

## Global Constraints

- No `.system(size:)` (build lint). No remote SPM packages.
- All colors/spacing/radius/typography through `DesignSystem` tokens.
- Views are `@MainActor`; services `@Observable @MainActor`.
- `xcodegen generate` after adding files; then `git checkout -- Nimbus/FileProviderExtension/Info.plist`.
- Build with `-allowProvisioningUpdates` via XcodeBuildMCP; run `NimbusTests`.

## Review Focus

1. A remote whose `about` lacks `total` (S3, alias, SFTP): no gauge, no sidebar bar, subtitle shows provider only. Test in Task 1.
2. A transfer whose `srcFs` is `"Backups:x"` and `dstFs` is `"Personal Drive:y"` appears under both volumes. Test in Task 5.
3. Deleting the selected remote while its Settings tab is open falls back to the first remote (existing `nextSelection`). Covered by `SidebarSelectionTests`.
4. File Provider toggle semantics (intent first, reconcile later) must survive the move into the Finder tab; the toggle code is reused, not rewritten (Task 6).
5. Toolbar items from `BrowserToolbar` must disappear when a non-Files tab is selected, or ⌘N creates folders from the Settings tab (Task 4).

---

### Task 1: Quota model and service

**Files:**
- Create: `Nimbus/Nimbus/State/StorageQuota.swift`
- Modify: `Nimbus/Nimbus/Services/RemoteStatusService.swift`
- Test: `Nimbus/NimbusTests/StorageQuotaTests.swift`

**Interfaces:**
- Produces: `struct StorageQuota: Equatable { let used: Int64?; let total: Int64?; var free: Int64?; var fraction: Double?; var usedText: String?; var totalText: String?; var isNearlyFull: Bool; init(about: AboutResponse); init(used:total:) }`
- Produces: `RemoteStatusService.quotas: [String: StorageQuota]`, `func refreshQuota(_ name: String) async`; `probe(_:)` stores the quota on success.

- [ ] Write `StorageQuotaTests`: `fractionIsNilWithoutTotal`, `fractionAndFreeFromUsedAndTotal` (1_280_000_000_000 of 2_000_000_000_000 → 0.64, free 720 GB), `nearlyFullAbove90Percent`, `textsUseByteCountFormatter`.
- [ ] Run tests, expect compile failure.
- [ ] Implement `StorageQuota`; `isNearlyFull` is `fraction >= 0.9`.
- [ ] Add `quotas` and `refreshQuota` to `RemoteStatusService`; `probe` sets `quotas[name] = StorageQuota(about:)` on success, removes it on failure; `clear` removes it.
- [ ] Run tests, expect pass. Commit `feat(volumes): storage quota model and per-remote quota cache`.

### Task 2: Provider directory

**Files:**
- Create: `Nimbus/Nimbus/Services/ProviderDirectory.swift`
- Modify: `Nimbus/Nimbus/NimbusApp.swift` (environment + load in `onDaemonConnected`)

**Interfaces:**
- Produces: `@Observable @MainActor final class ProviderDirectory { private(set) var descriptions: [String: String]; func load(client: RcloneClient) async; func displayName(forType: String) -> String }` where `displayName` falls back to the raw type capitalized.

- [ ] Implement; inject with `.environment(providerDirectory)` on both scenes.
- [ ] Build. Commit `feat(volumes): provider directory for human-readable backend names`.

### Task 3: Sidebar becomes Volumes + Tools

**Files:**
- Modify: `Nimbus/Nimbus/Views/SidebarSelection.swift` (drop `.mounts`, `.transfers`)
- Modify: `Nimbus/Nimbus/Views/Sidebar.swift`, `Views/Remotes/RemotesSidebarSection.swift`, `Views/Remotes/SidebarRemoteRow.swift`, `Views/AppCommands.swift`, `Views/ContentView.swift`
- Test: `Nimbus/NimbusTests/SidebarSelectionTests.swift`

**Interfaces:**
- `RemotesSidebarSection.onRemotesLoaded: ([Remote]) -> Void` (was `[String]`).
- `SidebarRemoteRow(remote:status:quota: StorageQuota?, ...)` draws a 3 pt capacity bar under the row when `quota?.fraction != nil`; tint accent, `statusWarning` when `isNearlyFull`.

- [ ] Update `SidebarSelectionTests` to drop the `.mounts/.transfers` expectations and keep `.copySync`.
- [ ] Remove the cases; section header "Volumes"; "Tools" section holds Copy & Sync; `AppCommands` Go menu: remove Mounts/Transfers items, keep Copy / Sync at ⌘⇧4.
- [ ] `ContentView` keeps `remotes: [Remote]` and renders `VolumeView(remote:)` (Task 4) for `.remote(name)`; the `.mounts`/`.transfers` cases are deleted.
- [ ] Build + tests. Commit `feat(volumes): sidebar lists volumes with capacity bars; Finder and Transfers panes removed`.

### Task 4: VolumeView shell with header, gauge, tabs, Files

**Files:**
- Create: `Nimbus/Nimbus/Views/Volume/VolumeView.swift`, `Views/Volume/VolumeHeader.swift`, `Views/Volume/StorageGauge.swift`, `Views/Volume/VolumeTabBar.swift`
- Modify: `Views/Browser/BrowserView.swift` (no changes to behavior; it is embedded as the Files tab)

**Interfaces:**
- `enum VolumeTab: String, CaseIterable { case files, transfers, finder, settings }`
- `VolumeView(remote: Remote, browseTarget: BrowseTarget?, onSync: (String) -> Void)`
- `VolumeHeader(remote:providerName:quota:isInFinder:onPrimary:onSync:onEdit:)`
- `StorageGauge(quota: StorageQuota)` hidden by caller when `quota.fraction == nil`.
- `VolumeTabBar(selection: Binding<VolumeTab>)` underline style from tokens.

- [ ] Build the shell; Files tab embeds `BrowserView`; other tabs show placeholder `EmptyState`s for now.
- [ ] `BrowserView`'s `.toolbar` only applies when the Files tab is selected: wrap the `BrowserToolbar` modifier in `if tab == .files` at the `VolumeView` level by passing `showsToolbar: Bool` into `BrowserView`.
- [ ] `.task(id: remote.name)` calls `statusService.refreshQuota(remote.name)` and repeats every 300 s.
- [ ] Build, run, screenshot. Commit `feat(volumes): volume pane with header, storage gauge and tabs`.

### Task 5: Transfers tab

**Files:**
- Modify: `Views/Transfers/TransfersView.swift` (`var remoteFilter: String? = nil`), `State/TransferStore.swift` (static `func involves(_ transfer: Transfer, remote: String) -> Bool`)
- Test: `Nimbus/NimbusTests/TransferRemoteFilterTests.swift`

- [ ] Test: transfer with `srcFs: "Backups:x"`, `dstFs: "Personal Drive:y"` involves both, not "Personal"; `"Personal Drive2:z"` does not involve "Personal Drive".
- [ ] Implement `involves` (prefix match on `"<remote>:"`); `TransfersView` filters active/completed through it when `remoteFilter` is set; empty-state copy "No transfers for this volume yet."
- [ ] Wire into `VolumeView` `.transfers`. Commit `feat(volumes): per-volume transfers tab`.

### Task 6: Finder tab and header verb

**Files:**
- Modify: `Views/Mounts/MountsView.swift` (`var remoteFilter: String? = nil`; when set, hides `finderHeader`, filters `configs.configs`, and `AddMountSheet` preselects the remote via new `initialRemote: String?`), `Views/Mounts/AddMountSheet.swift`
- Modify: `Views/Volume/VolumeView.swift`

- [ ] `VolumeView` computes `isInFinder = !settings.disabledFileProviderDomains.contains(name) && fileProviderBridge.activeDomains.contains(name)`.
- [ ] Primary verb: "Open in Finder" → `fileProviderBridge.urlForItem(remote:path:"")` then `NSWorkspace.shared.open`; "Show in Finder" → the same add-domain sequence `MountsView.toggle` uses for `.fileProvider` (extract into `FinderIntegration.enable(remote:settings:bridge:)` static helper in a new `Services/FinderIntegration.swift` and call it from both).
- [ ] Finder tab empty state: "Show in Finder" and "Mount as Network Volume…" buttons.
- [ ] Build, run, toggle once against a demo remote. Commit `feat(volumes): Finder tab and Show in Finder verb`.

### Task 7: Settings tab

**Files:**
- Create: `Views/Volume/VolumeSettingsTab.swift`

- [ ] `FormSection("Configuration")` rows for `type` and each non-secret config key (skip keys containing `token`, `pass`, `secret`, `key`), `Edit Configuration…` → `EditRemoteSheet`, `Remove Volume…` → existing confirmation dialog copy, then `statusService.clear` and reload.
- [ ] Commit `feat(volumes): settings tab`.

### Task 8: Transfer drawer and toolbar pill

**Files:**
- Create: `Views/Volume/TransferDrawer.swift`, `Views/Volume/TransferToolbarPill.swift`

- [ ] Drawer: shown when `transferStore.activeTransfers` is non-empty; header "Transfers · N active · <speed>"; up to 4 `TransferRow`s; "+N more" switches tab to `.transfers`; collapse chevron with session `@State`.
- [ ] Pill: `ToolbarItem(placement: .status)` capsule "N items to <dest remote>" with `ProgressView(value:)` 60 pt wide; tap → `.transfers` tab.
- [ ] Commit `feat(volumes): transfer drawer and toolbar progress pill`.

### Task 9: Inspector

**Files:**
- Create: `Views/Volume/FileInspector.swift`
- Modify: `State/AppSettings.swift` (`inspectorVisible: Bool`, default false), `Views/Browser/BrowserView.swift` (expose `viewModel.selection` + `sortedFiles` to the inspector via a `BrowserSelectionSnapshot` published through `.preference` or by hoisting `BrowserViewModel` creation into `VolumeView`)

- [ ] Hoist: `VolumeView` owns `@State var browserModel: BrowserViewModel?` and passes it to `BrowserView(model:)`; inspector reads `model.selection.ids` and `model.sortedFiles`.
- [ ] Inspector content per spec; actions Quick Look (reuse `QuickLookHost` path from `BrowserView.previewFiles`) and Copy to… (opens `FolderBrowserSheet` for a chosen destination remote, then `ConfirmCopySheet`).
- [ ] Toolbar toggle `sidebar.right` bound to `settings.inspectorVisible`.
- [ ] Commit `feat(volumes): file inspector`.

### Task 10: Sync prefill, copy, screenshots

- [ ] `CopySyncView(initialSource: String?)`; `ContentView` keeps `@State copySyncSource` set by `onSync`.
- [ ] Onboarding secondary action text "Show it in Finder".
- [ ] Capture `docs/screenshots/volume.png` (replace `browser-list.png` usage in README later). Update spec status. Commit `feat(volumes): sync prefill and screenshots`.
