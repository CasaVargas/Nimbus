# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Nimbus** is a native macOS cloud storage manager built in SwiftUI (Swift 6) with a Swift File Provider extension for Finder integration. It uses **rclone** as the cloud backend (spawned as a subprocess, never reimplemented) to support 50+ cloud providers (S3, Google Drive, OneDrive, etc.).

> The previous Tauri (Rust + React) build is deprecated. Its sources are frozen under `legacy/tauri/` and on the `tauri-eol` branch. See `DEPRECATED.md`.

## Build & Development Commands

Prefer **XcodeBuildMCP** tools over raw `xcodebuild` when invoking builds from Claude Code.

```bash
# Regenerate Xcode project from project.yml (run after editing project.yml or adding files)
cd Nimbus && xcodegen generate

# Open in Xcode for development
cd Nimbus && open Nimbus.xcodeproj

# Build (Debug) from CLI
xcodebuild \
  -project Nimbus/Nimbus.xcodeproj \
  -scheme Nimbus \
  -destination 'platform=macOS' \
  build

# Full release build
bash scripts/build-release.sh

# Tests (app). RcloneConfigMachineTests pins an older rclone's question order;
# CI skips it, so skip it locally too unless you're working on it.
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' \
  test -skip-testing:NimbusTests/RcloneConfigMachineTests

# A single test class or method
xcodebuild -project Nimbus/Nimbus.xcodeproj -scheme Nimbus -destination 'platform=macOS' \
  test -only-testing:NimbusTests/BackupStoreTests[/testMethodName]

# RcloneKit package tests
cd RcloneKit && swift test
```

- **`xcodegen generate` rewrites `Nimbus/FileProviderExtension/Info.plist`** with literal version numbers. Always follow it with `git checkout -- Nimbus/FileProviderExtension/Info.plist` (CI does), or the extension's version stops tracking the app's.
- Without a signing team, add `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO` (the app-group entitlements otherwise demand a profile). Local signing: copy `Nimbus/Local.xcconfig.example` to `Nimbus/Local.xcconfig` and set `DEVELOPMENT_TEAM`.
- Build phases run lints that fail the build: `scripts/lint-no-system-size.sh` (no `.system(size:)` outside `DesignSystem/`; use the semantic typography helpers) and `scripts/lint-package-resolved.sh`. CI also runs `scripts/lint-release-notes.sh`.
- Snapshot tests (e.g. `GuidedAddRemoteSnapshotTests`) render at a fixed 2x, each in its own window; see `SnapshotHelpers` in `NimbusTests/`.

### Prerequisites

- macOS 15.0+ deployment target
- **Xcode 27+.** Earlier Xcode versions crash in IRGen compiling this project (see `.github/workflows/ci.yml`).
- XcodeGen (`brew install xcodegen`)
- rclone binary in PATH (default `/usr/local/bin/rclone`, configurable in settings)

## Architecture

```
SwiftUI app (Nimbus/Nimbus/) ──▶ RcloneKit ──HTTP──▶ rclone daemon ──▶ Cloud providers
                                     ▲
                                     │
File Provider extension (Nimbus/FileProviderExtension/) ───────────────▶ Finder
```

- The SwiftUI app spawns the rclone daemon as a subprocess and talks to it over HTTP via `RcloneKit`.
- The File Provider extension also uses `RcloneKit` to talk to the same daemon, exposing remotes in Finder.
- NFS mounting is handled in-process by `MountManager` (spawns `rclone serve nfs`, calls `mount_nfs`).

**State sync between app and extension:** App group UserDefaults (`53MUTM55LC.app.casavargas.nimbus`) — rclone port and remote configs are broadcast to the extension via the shared container.

### Key Layers

| Layer | Location | Tech |
|-------|----------|------|
| SwiftUI app | `Nimbus/Nimbus/` | Swift 6, SwiftUI, `@Observable`, macOS 15.0 |
| RcloneKit | `RcloneKit/` | Local Swift package — typed HTTP client for rclone RC API |
| File Provider | `Nimbus/FileProviderExtension/` | Swift 6 — `NSFileProviderReplicatedExtension`, uses RcloneKit |
| Xcode project | `Nimbus/project.yml` | XcodeGen → `Nimbus.xcodeproj` |
| Build scripts | `scripts/` | Shell — orchestrate XcodeGen + xcodebuild |

### SwiftUI App Organization (`Nimbus/Nimbus/`)

- `Views/` — SwiftUI views organized by feature (`Browser/`, `Remotes/`, `Transfers/`, `Mounts/`, `Settings/`)
- `ViewModels/` — `@Observable @MainActor` view models (`BrowserViewModel`, `RemotesViewModel`, etc.)
- `Services/` — `RcloneDaemon` (subprocess lifecycle), `MountManager` (NFS), `FileProviderBridge` (domain registration)
- `State/` — `TransferStore` (copy/sync job tracking), `AppRouter` (one-shot routes from the menu bar companion / notifications into the main window; the view that owns a route `take`s it)

`Nimbus/Shared/` is compiled into **both** the app and the File Provider extension (app group, pins, capabilities, change diffs), so code there must build for both. `Nimbus/LaunchAgents/` holds the background backups agent plist, registered with `SMAppService.agent(plistName:)`.

### File Provider Extension (`Nimbus/FileProviderExtension/`)

- `Extension.swift` — Main `NSFileProviderReplicatedExtension` (item fetch, contents, create/modify/delete)
- `Item.swift` — File/folder representation; identifiers are always `"<remoteName>:<fullPathFromRemoteRoot>"`
- `Enumerator.swift` — Directory enumeration + snapshot-diff change tracking
- `SystemContainerEnumerator.swift` — Empty enumerator for `.workingSet` / `.trashContainer`
- `SyncSnapshotStore.swift` — Persisted per-container listing snapshots (sync anchors)
- `RetrySupport.swift` — Shared retry helper; re-reads the daemon port (app group UserDefaults → group container JSON → extension container JSON) each attempt
- Talks to the rclone daemon via RcloneKit

### RcloneKit (`RcloneKit/`)

- `final class: @unchecked Sendable` (not an actor) to avoid actor hop overhead
- Port mutation only happens from MainActor during startup
- Typed wrappers over rclone's RC API

## Bundle Identifiers

All apps and extensions use the `app.casavargas.nimbus` bundle ID family:

| Component | Bundle ID |
|-----------|-----------|
| SwiftUI app | `app.casavargas.nimbus` |
| File Provider extension | `app.casavargas.nimbus.FileProvider` |
| App group | `53MUTM55LC.app.casavargas.nimbus` |
| Logger subsystem (main) | `app.casavargas.nimbus` |
| Logger subsystem (extension) | `app.casavargas.nimbus.FileProvider` |

## Code Signing

- **Development:** `Apple Development: Jonathan Vargas (4JQT5BXA8Q)`
- **Release:** `Developer ID Application: Jonathan Vargas (53MUTM55LC)`

## Configuration

| File | Purpose |
|------|---------|
| `Nimbus/project.yml` | XcodeGen project definition: Swift 6.0, macOS 15.0 target, app + extension targets |
| `Nimbus/Nimbus/Nimbus.entitlements` | Sandbox: network client/server, app group, File Provider |
| `RcloneKit/Package.swift` | Swift package manifest for RcloneKit |

## Conventions

- Rclone RC API is called directly from SwiftUI view models via `RcloneKit` (no extra IPC layer).
- The rclone daemon port starts at 5572 and is shared with the File Provider extension via App Group UserDefaults.
- NFS servers use ports starting at 19049.
- View models are `@Observable @MainActor`; services own background work via actors or `@unchecked Sendable` classes where justified.
- New features land under `Nimbus/Nimbus/Views/<Feature>/` plus matching `ViewModels/` entries.
- Sparkle (updates) is the only remote Swift package; `scripts/lint-package-resolved.sh` fails the build on any other. It is linked by the app target only, never the File Provider extension.
- `CFBundleVersion` equals `MARKETING_VERSION` (Sparkle orders updates by it): bump `MARKETING_VERSION` in `Nimbus/project.yml` and nothing else.
- In a `List`, never put `.sheet`, `.alert`, `.confirmationDialog` or `.onChange` on a `Section`/`Group`: SwiftUI copies them onto every row, so one binding presents N stacked sheets (the 1.2.0 Add Cloud bug). Attach them to a view that exists once.

## Releasing

1. One PR: bump `MARKETING_VERSION`, regenerate the project, and add `docs/releases/<version>.md`. Copy the structure of the previous version's notes; the checksum line reads `(filled in when the signed DMG is built)`. The notes must end with the footer from `docs/releases/FOOTER.md`, with `utm_content=<version>` (enforced by `lint-release-notes.sh`).
2. After merging, push tag `v<version>`. `.github/workflows/release.yml` builds a universal binary, signs it with Developer ID, notarizes it, signs it for Sparkle and creates a **draft** release with the DMG, `.sha256` and `appcast.xml`.
3. Publishing the draft is what ships it: installed copies read `releases/latest/download/appcast.xml`.
4. Follow-up PR: record the checksum in `docs/releases/<version>.md`.

## Historical Context

- `legacy/tauri/` — Frozen Tauri + React sources, kept for reference only. Do not build.
- `tauri-eol` branch — Last working Tauri state before the SwiftUI cutover.
- Strategic context: `docs/superpowers/specs/2026-05-14-nimbus-north-star-design.md` and `docs/superpowers/specs/2026-05-14-phase1-foundation-browser-design.md`.
