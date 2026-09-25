<h1 align="center">Nimbus</h1>

<p align="center">
  A native macOS cloud storage manager with Finder integration.<br>
  One app to browse, mount, and sync across 50+ cloud providers.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2015%2B-blue" alt="macOS 15+">
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
SwiftUI views ──▶ RcloneKit ──HTTP──▶ rclone daemon ──▶ Cloud providers
                      ▲
                      │
File Provider extension (Swift) ────▶ Finder
```

| Layer | Tech |
|-------|------|
| App | SwiftUI (Swift 6, macOS 15.0, `@Observable` view models) |
| Rclone client | RcloneKit — local Swift package, typed HTTP client over the rclone RC API |
| File Provider | Swift 6 — `NSFileProviderReplicatedExtension` for Finder integration |
| Cloud backend | rclone (spawned as subprocess, never reimplemented) |

## Getting Started

### Prerequisites

- macOS 15.0+
- Xcode + Command Line Tools
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- [rclone](https://rclone.org/install/) in PATH

### Development

```bash
# Generate the Xcode project from project.yml
cd Nimbus && xcodegen generate

# Open in Xcode
cd Nimbus && open Nimbus.xcodeproj
```

### Release Build

```bash
bash scripts/build-release.sh
```

This regenerates the Xcode project and produces a release `.app` at `Nimbus/build/Build/Products/Release/Nimbus.app`.

## Project Structure

```
Nimbus/                       # SwiftUI app + Xcode project
  Nimbus/                     # App sources (Views, ViewModels, Services, State)
  FileProviderExtension/      # NSFileProviderReplicatedExtension
  project.yml                 # XcodeGen project definition

RcloneKit/                    # Local Swift package — typed rclone RC API client
scripts/                      # Build scripts (build-release.sh)
docs/superpowers/             # Design specs and implementation plans
```

## License

Not chosen yet. There is no LICENSE file, so until one is added all rights are
reserved by CasaVargas LLC.

---

### Legacy

The original Tauri (Rust + React) build is end-of-life. Its sources are preserved at `legacy/tauri/` for reference, and the last working Tauri state is frozen on the [`tauri-eol`](https://github.com/CasaVargas/Nimbus/tree/tauri-eol) branch. See [`DEPRECATED.md`](DEPRECATED.md).
