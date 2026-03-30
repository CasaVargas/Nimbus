# File Provider Release Pipeline & Cloud Badges Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire the File Provider extension `.appex` into the Tauri release build so macOS discovers it, and fix `FileProviderItem` to report cloud-backed content policy for Finder badges/context menus.

**Architecture:** A top-level shell script orchestrates the full release build: frontend → extension → Tauri app → embed `.appex` into `.app/Contents/PlugIns/`. The `beforeBuildCommand` in `tauri.conf.json` is updated to skip the extension build (the wrapper script handles sequencing). `FileProviderItem` gains `contentPolicy` and `.allowsEvicting` capability.

**Tech Stack:** Bash (build scripts), Swift 6 (FileProviderItem), Tauri 2 config

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `scripts/build-release.sh` | **Create** | Top-level release build orchestrator |
| `src-tauri/tauri.conf.json` | **Modify** | Update `beforeBuildCommand` to not duplicate extension build when called from wrapper |
| `src-tauri/FileProviderExtension/FileProviderItem.swift` | **Modify** | Add `contentPolicy`, update `capabilities` |
| `package.json` | **Modify** | Add `build:release` npm script for convenience |

---

### Task 1: Create release build orchestrator script

**Files:**
- Create: `scripts/build-release.sh`

- [ ] **Step 1: Create the scripts directory and build-release.sh**

```bash
#!/bin/bash
set -euo pipefail

# Full release build: frontend → extension → Tauri app → embed extension
# Usage: ./scripts/build-release.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

echo "=== Step 1/4: Building frontend ==="
npm run build

echo "=== Step 2/4: Building File Provider extension ==="
(cd src-tauri && bash build-extension.sh --release)

echo "=== Step 3/4: Building Tauri app ==="
cargo tauri build

echo "=== Step 4/4: Embedding extension into app bundle ==="
bash src-tauri/scripts/embed-extension.sh --release

echo ""
echo "=== Release build complete ==="
echo "App bundle: src-tauri/target/release/bundle/macos/Nimbus.app"
```

- [ ] **Step 2: Make the script executable**

Run: `chmod +x scripts/build-release.sh`

- [ ] **Step 3: Commit**

```bash
git add scripts/build-release.sh
git commit -m "feat: add release build script that embeds File Provider extension"
```

---

### Task 2: Update tauri.conf.json to avoid double-building the extension

The current `beforeBuildCommand` runs `npm run build && cd src-tauri && bash build-extension.sh --release`. When invoked via `scripts/build-release.sh`, steps 1 and 2 have already run, so `beforeBuildCommand` would duplicate them. Update it to be a no-op when the wrapper script is used, while keeping it functional for direct `cargo tauri build` invocation.

**Files:**
- Modify: `src-tauri/tauri.conf.json:9`

- [ ] **Step 1: Update beforeBuildCommand**

The `beforeBuildCommand` currently does both frontend and extension build. Since `cargo tauri build` runs this automatically, we need it for standalone `cargo tauri build` calls. But the wrapper script already does both steps before invoking `cargo tauri build`.

The simplest approach: keep `beforeBuildCommand` as-is. The frontend build and extension build are both idempotent — running them twice is harmless (just a few extra seconds). This avoids fragile environment-variable-based skipping.

**No change needed to `tauri.conf.json`.** The wrapper script adds the missing embed step; the existing `beforeBuildCommand` is fine to run redundantly.

- [ ] **Step 2: Verify by reading the config**

Run: `cat src-tauri/tauri.conf.json | grep beforeBuildCommand`
Expected: `"beforeBuildCommand": "npm run build && cd src-tauri && bash build-extension.sh --release",`

---

### Task 3: Add npm convenience script

**Files:**
- Modify: `package.json:6-13` (scripts section)

- [ ] **Step 1: Add build:release script to package.json**

In the `"scripts"` section of `package.json`, add after the existing `"tauri"` entry:

```json
"build:release": "bash scripts/build-release.sh"
```

The full scripts section becomes:
```json
"scripts": {
    "dev": "vite",
    "build": "tsc && vite build",
    "preview": "vite preview",
    "test": "vitest run",
    "test:watch": "vitest",
    "tauri": "tauri",
    "build:release": "bash scripts/build-release.sh"
}
```

- [ ] **Step 2: Commit**

```bash
git add package.json
git commit -m "feat: add npm build:release script for full release with extension"
```

---

### Task 4: Add contentPolicy to FileProviderItem

**Files:**
- Modify: `src-tauri/FileProviderExtension/FileProviderItem.swift:46-51`

- [ ] **Step 1: Add contentPolicy property**

After the `capabilities` property (line 51), add the `contentPolicy` property. In `FileProviderItem.swift`, after:

```swift
    var capabilities: NSFileProviderItemCapabilities {
        if isFolder {
            return [.allowsReading, .allowsContentEnumerating, .allowsAddingSubItems, .allowsRenaming, .allowsDeleting]
        }
        return [.allowsReading, .allowsWriting, .allowsRenaming, .allowsDeleting]
    }
```

Add:

```swift
    var contentPolicy: NSFileProviderContentPolicy {
        .downloadLazily
    }
```

This tells macOS that items are cloud-backed and should only be downloaded when the user accesses them. The system uses this to show cloud status badges (download arrow for not-yet-downloaded, checkmark for local).

- [ ] **Step 2: Update capabilities to include .allowsEvicting**

Replace the existing `capabilities` property:

```swift
    var capabilities: NSFileProviderItemCapabilities {
        if isFolder {
            return [.allowsReading, .allowsContentEnumerating, .allowsAddingSubItems, .allowsRenaming, .allowsDeleting]
        }
        return [.allowsReading, .allowsWriting, .allowsRenaming, .allowsDeleting]
    }
```

With:

```swift
    var capabilities: NSFileProviderItemCapabilities {
        if isFolder {
            return [.allowsReading, .allowsContentEnumerating, .allowsAddingSubItems, .allowsRenaming, .allowsDeleting]
        }
        return [.allowsReading, .allowsWriting, .allowsRenaming, .allowsDeleting, .allowsEvicting]
    }
```

The `.allowsEvicting` capability enables the "Remove Download" context menu item in Finder, allowing users to free local disk space for files they no longer need cached.

- [ ] **Step 3: Build the extension to verify it compiles**

Run: `cd src-tauri && bash build-extension.sh`
Expected: Output ending with `File Provider build complete.` and no errors.

- [ ] **Step 4: Commit**

```bash
git add src-tauri/FileProviderExtension/FileProviderItem.swift
git commit -m "feat: add cloud content policy and eviction capability to FileProviderItem"
```

---

### Task 5: Full release build verification

- [ ] **Step 1: Run the full release build**

Run: `npm run build:release`
Expected: All 4 steps complete. Output includes:
- `Building frontend` → succeeds
- `Building File Provider extension (Release)` → succeeds
- `Building Tauri app` → produces `.app` bundle
- `Embedding File Provider extension into: .../Nimbus.app` → succeeds
- `Extension embedding complete.`

- [ ] **Step 2: Verify the .appex is inside the bundle**

Run: `ls src-tauri/target/release/bundle/macos/Nimbus.app/Contents/PlugIns/`
Expected: `FileProviderExtension.appex`

Run: `ls src-tauri/target/release/bundle/macos/Nimbus.app/Contents/MacOS/fp-domain-manager`
Expected: File exists.

- [ ] **Step 3: Verify codesigning**

Run: `codesign --verify --deep --strict src-tauri/target/release/bundle/macos/Nimbus.app`
Expected: No output (means valid signature).

- [ ] **Step 4: Launch the app and verify extension registration**

Launch: `open src-tauri/target/release/bundle/macos/Nimbus.app`

After the app opens and registers a domain (mount a remote), check:
Run: `pluginkit -m -i com.nimbus.app.FileProvider`
Expected: Output showing the extension is registered.

- [ ] **Step 5: Verify Finder integration**

In Finder:
1. The File Provider location should appear in the sidebar
2. Files should show cloud status badges (download arrow icons)
3. Right-click a file → "Download Now" and "Keep Downloaded" options should appear
4. After downloading a file, right-click → "Remove Download" should appear

- [ ] **Step 6: Commit any fixes if needed, then final commit**

```bash
git add -A
git commit -m "chore: verify release build pipeline with embedded File Provider extension"
```
