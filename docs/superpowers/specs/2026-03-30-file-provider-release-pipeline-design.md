# File Provider Release Pipeline & Cloud Badges Fix

**Date:** 2026-03-30
**Status:** Approved

## Problem

The File Provider extension (`FileProviderExtension.appex`) builds successfully but is never embedded into the Tauri app bundle. macOS discovers File Provider extensions only when they reside at `App.app/Contents/PlugIns/Extension.appex`. As a result:

- `pluginkit -m -i com.nimbus.app.FileProvider` returns nothing — the system doesn't know the extension exists
- No cloud status badges appear on files in Finder
- No "Download Now" / "Keep Downloaded" / "Remove Download" context menu items
- The extension code has never been loaded by the system

Additionally, `FileProviderItem` is missing properties that macOS requires to treat items as cloud-backed with on-demand download semantics.

## Root Cause

1. **Build pipeline gap:** `build-extension.sh` compiles the `.appex` to `target/extension/`, and `scripts/embed-extension.sh` copies it into the `.app` bundle — but `embed-extension.sh` is never called. Tauri 2 has no `afterBuildCommand`, so the embed step falls through the cracks.

2. **Missing item properties:** `FileProviderItem` doesn't declare `contentPolicy` (`.downloadLazily`) or the `.allowsEvicting` capability, so even if the extension loaded, macOS wouldn't surface cloud-specific UI.

## Solution

### Part 1: Release Build Pipeline

Create a top-level build script that orchestrates the full release sequence, since Tauri can't run post-build hooks:

**`scripts/build-release.sh`:**
1. Build frontend (`npm run build`)
2. Build File Provider extension (`src-tauri/build-extension.sh --release`)
3. Build Tauri app (`cargo tauri build` — produces `.app` bundle)
4. Embed extension into `.app` (`src-tauri/scripts/embed-extension.sh --release`)

**`tauri.conf.json` changes:**
- `beforeBuildCommand` should only handle frontend build + extension build (steps 1-2), not the embed step. The embed must run after Tauri produces the `.app`.
- Update to: `"npm run build && cd src-tauri && bash build-extension.sh --release"`

This is already what `beforeBuildCommand` does today, so the only new piece is the wrapper script that calls `cargo tauri build` then `embed-extension.sh` in sequence.

### Part 2: FileProviderItem Cloud Properties

Add two properties to `FileProviderItem.swift`:

**`contentPolicy`** — tells macOS these are cloud-backed files that should be downloaded on demand:
```swift
var contentPolicy: NSFileProviderContentPolicy {
    .downloadLazily
}
```

**Updated `capabilities`** — add `.allowsEvicting` for files so "Remove Download" appears in context menus:
```swift
var capabilities: NSFileProviderItemCapabilities {
    if isFolder {
        return [.allowsReading, .allowsContentEnumerating, .allowsAddingSubItems,
                .allowsRenaming, .allowsDeleting]
    }
    return [.allowsReading, .allowsWriting, .allowsRenaming, .allowsDeleting, .allowsEvicting]
}
```

Download/upload state tracking is handled automatically by the `NSFileProviderReplicatedExtension` framework based on `fetchContents()` calls. No manual state management needed.

## Files Modified

- `scripts/build-release.sh` — **new** — top-level release build orchestrator
- `src-tauri/FileProviderExtension/FileProviderItem.swift` — add `contentPolicy`, update `capabilities`

## Verification

After building with the release script:
1. `pluginkit -m -i com.nimbus.app.FileProvider` should return the extension
2. File Provider location in Finder should show cloud status badges (download arrows on unmaterialized files, checkmarks on downloaded files)
3. Right-click should show "Download Now" / "Keep Downloaded" / "Remove Download" actions
