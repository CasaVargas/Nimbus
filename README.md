<p align="center">
  <img src="src-tauri/icons/128x128@2x.png" width="128" height="128" alt="Nimbus icon">
</p>

<h1 align="center">Nimbus</h1>

<p align="center">
  A native macOS cloud storage manager with Finder integration.<br>
  One app to browse, mount, and sync across 50+ cloud providers.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2013%2B-blue" alt="macOS 13+">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
</p>

---

## What is Nimbus?

Nimbus brings all your cloud storage into one place on macOS. Powered by [rclone](https://rclone.org), it supports S3, Google Drive, OneDrive, Dropbox, and dozens more — without vendor lock-in.

- **Finder integration** — Browse cloud files directly in Finder via a native File Provider extension
- **NFS mounting** — Mount any remote as a local volume on your Mac
- **File browser** — Grid and table views with drag-and-drop, context menus, and quick actions
- **Copy & Sync** — Transfer files between any two remotes or local folders
- **Transfer monitoring** — Track active transfers with progress and speed stats

## Architecture

```
React UI ──Tauri IPC──▶ Rust backend
     │                       │
     │                       ├─ spawns rclone daemon
     │                       ├─ spawns rclone serve nfs
     ▼                       └─ mount_nfs system call
rclone RC API
     ▲
     │
File Provider Extension (Swift) ──▶ Finder
```

| Layer | Tech |
|-------|------|
| Frontend | React 19, TypeScript, Tailwind CSS 4, Zustand, TanStack Query |
| Backend | Tauri 2 (Rust) — rclone lifecycle, NFS mounts, File Provider domains |
| File Provider | Swift 6 — NSFileProviderReplicatedExtension for Finder integration |
| Cloud backend | rclone (spawned as subprocess, never reimplemented) |

## Getting Started

### Prerequisites

- macOS 13.0+
- Xcode + Command Line Tools
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- Rust toolchain (2021 edition)
- Node.js + npm
- [rclone](https://rclone.org/install/) in PATH

### Development

```bash
# Install dependencies
npm install

# Run in development mode (Vite dev server + Tauri)
npm run dev

# Build the File Provider extension
bash src-tauri/build-extension.sh

# Run tests
npm run test
```

### Release Build

```bash
bash scripts/build-release.sh
```

This runs a 4-step pipeline:
1. Frontend build (`npm run build`)
2. Swift File Provider extension (`build-extension.sh --release`)
3. Rust + app bundle (`cargo tauri build --bundles app`)
4. Embed extension and re-sign

## Project Structure

```
src/                          # React frontend
  features/                   # Feature modules (browser, remotes, mounts, transfers, etc.)
  stores/                     # Zustand state management
  hooks/                      # Global hooks (daemon lifecycle, auto-mount, etc.)

src-tauri/
  src/commands/               # Tauri IPC commands (Rust)
  FileProviderExtension/      # Swift File Provider for Finder integration

Nimbus/                       # SwiftUI native rewrite (in progress)
RcloneKit/                    # Swift package for rclone RC API
```

## License

MIT
