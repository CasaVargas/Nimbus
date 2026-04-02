# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Nimbus** is a macOS cloud storage manager built with Tauri 2 (Rust backend + React frontend) and a native Swift File Provider extension for Finder integration. It uses **rclone** as the cloud backend (spawned as a subprocess, never reimplemented) to support 50+ cloud providers (S3, Google Drive, OneDrive, etc.).

A full SwiftUI native rewrite is planned — see `2026-03-31-swift-swiftui-rewrite-design.md`.

## Build & Development Commands

```bash
# Development
npm run dev                        # Vite dev server + Tauri

# Frontend build
npm run build                      # TypeScript check + Vite bundle to dist/

# Tests
npm run test                       # Vitest unit tests
npm run test:watch                 # Watch mode

# Lint & Format
npx biome check --apply            # Format + lint (Biome)
npx biome format                   # Format only
npx biome lint                     # Lint only

# Swift File Provider extension
bash src-tauri/build-extension.sh              # Debug build
bash src-tauri/build-extension.sh --release    # Release build (XcodeGen → xcodebuild → sign)

# Full release build (4-step pipeline)
bash scripts/build-release.sh
# 1. npm run build (frontend)
# 2. build-extension.sh --release (Swift extension)
# 3. cargo tauri build --bundles app (Rust + app bundle)
# 4. embed-extension.sh --release (embed .appex, re-sign in /tmp to avoid iCloud xattr issues)
```

### Prerequisites

- macOS 13.0+ deployment target
- Xcode + CLI tools, XcodeGen (`brew install xcodegen`)
- Rust (2021 edition), Node.js + npm
- rclone binary in PATH (default `/usr/local/bin/rclone`, configurable in settings)

## Architecture

```
React UI (src/) ──Tauri IPC──▶ Rust backend (src-tauri/src/)
     │                              │
     │ HTTP (rclone RC API)         │ spawns rclone daemon
     ▼                              │ spawns rclone serve nfs
rclone daemon ◀─────────────────────┘
     │                              │ mount_nfs system call
     ▼                              ▼
Cloud providers              NFS mount points

File Provider Extension (Swift) ──HTTP──▶ rclone RC API
     │
     ▼
Finder integration
```

**State sync between app and extension:** App group UserDefaults (`group.app.casavargas.nimbus`) — rclone port and remote configs are broadcast to the extension via shared container.

### Key Layers

| Layer | Location | Tech |
|-------|----------|------|
| Frontend UI | `src/` | React 19, TypeScript 5.8, Tailwind CSS 4, Zustand, TanStack Query |
| Tauri IPC | `src-tauri/src/commands/` | Rust — rclone daemon lifecycle, NFS mount/unmount, File Provider domain registration |
| File Provider | `src-tauri/FileProviderExtension/` | Swift 6 — Finder integration via NSFileProviderReplicatedExtension |
| Build scripts | `scripts/`, `src-tauri/scripts/` | Shell — orchestrate multi-step build + code signing |

### Frontend Organization (`src/`)

- `app/` — Shell: router (React Router 7), providers, theme
- `features/` — Feature modules: `browser/`, `remotes/`, `transfers/`, `mount/`, `copy-sync/`, `settings/`, `onboarding/`
- `stores/` — Zustand stores: `app-store.ts`, `mount-store.ts`, `transfer-store.ts`
- `hooks/` — Global hooks: `use-daemon.ts` (rclone lifecycle), `use-auto-mount.ts`, `use-file-provider-sync.ts`
- `components/` — Shared UI (sidebar, connection banner, etc.)
- Path alias: `@/*` maps to `./src/*`

### Tauri Commands (`src-tauri/src/commands/`)

- `rclone.rs` — Start/stop rclone daemon subprocess
- `nfs_mount.rs` — Mount/unmount NFS volumes (spawns `rclone serve nfs`, calls `mount_nfs`)
- `file_provider.rs` — Register/unregister File Provider domains via `fp-domain-manager` CLI

### Swift Extension (`src-tauri/FileProviderExtension/`)

- Built via XcodeGen (`project.yml` → Xcode project)
- `FileProviderExtension.swift` — Main NSFileProviderReplicatedExtension
- `FileProviderItem.swift` — File/folder representation
- `FileProviderEnumerator.swift` — Directory enumeration
- `RcloneClient.swift` — HTTP client to rclone RC API
- `SharedState.swift` — App group UserDefaults bridge
- `DomainManager.swift` — Standalone CLI for domain registration

### SwiftUI Native Rewrite (`Nimbus/`, `RcloneKit/`)

A native SwiftUI rewrite is in progress — see `2026-03-31-swift-swiftui-rewrite-design.md`.

| Layer | Location | Tech |
|-------|----------|------|
| SwiftUI App | `Nimbus/Nimbus/` | Swift 6, SwiftUI, @Observable, macOS 15.0 |
| RcloneKit | `RcloneKit/` | Swift package — typed HTTP client for rclone RC API |
| File Provider | `Nimbus/FileProviderExtension/` | Swift 6 — Finder integration (same as Tauri extension, uses RcloneKit) |
| Xcode project | `Nimbus/project.yml` | XcodeGen → `Nimbus.xcodeproj` |

**SwiftUI app organization:**
- `Views/` — SwiftUI views organized by feature (`Browser/`, `Remotes/`, `Transfers/`, `Mounts/`, `Settings/`)
- `ViewModels/` — `@Observable @MainActor` view models (`BrowserViewModel`, `RemotesViewModel`, etc.)
- `Services/` — `RcloneDaemon` (subprocess lifecycle), `MountManager` (NFS), `FileProviderBridge` (domain registration)
- `State/` — `TransferStore` (copy/sync job tracking)

**RcloneKit** is a `final class: @unchecked Sendable` (not an actor) to avoid actor hop overhead. Port mutation only happens from MainActor during startup.

```bash
# SwiftUI build (requires xcodegen)
cd Nimbus && xcodegen generate && xcodebuild -scheme Nimbus build
```

## Bundle Identifiers

All apps and extensions use the `app.casavargas.nimbus` bundle ID family:

| Component | Bundle ID |
|-----------|-----------|
| Tauri app | `app.casavargas.nimbus` |
| SwiftUI app | `app.casavargas.nimbus` |
| File Provider (both) | `app.casavargas.nimbus.FileProvider` |
| App group | `group.app.casavargas.nimbus` |
| Logger subsystem (main) | `app.casavargas.nimbus` |
| Logger subsystem (extension) | `app.casavargas.nimbus.FileProvider` |

## Code Signing

- **Development:** `Apple Development: Jonathan Vargas (4JQT5BXA8Q)`
- **Release:** `Developer ID Application: Jonathan Vargas (53MUTM55LC)`
- Release builds sign in `/tmp` to avoid iCloud xattr interference on the working directory

## Configuration

| File | Purpose |
|------|---------|
| `src-tauri/tauri.conf.json` | App identity (`app.casavargas.nimbus`), window config (1200x800), bundle settings |
| `src-tauri/Entitlements.plist` | Sandbox: network client/server, app group |
| `src-tauri/FileProviderExtension/project.yml` | XcodeGen: Swift 6.0, macOS 13.0 target |
| `biome.json` | Biome linter/formatter config |
| `vite.config.ts` | Vite + React plugin + Tailwind + path aliases + Vitest |

## Conventions

- Frontend uses **Biome** (not ESLint/Prettier) for formatting and linting
- Feature modules follow `features/<name>/` with `pages/`, `components/`, `hooks/` subdirs
- Rclone RC API is called directly from frontend via HTTP (not proxied through Tauri for most operations)
- The rclone daemon port starts at 5572 and is shared with the File Provider extension via UserDefaults
- NFS servers use ports starting at 19049
