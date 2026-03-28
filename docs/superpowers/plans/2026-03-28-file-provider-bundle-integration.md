# File Provider Bundle Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Get the Apple File Provider extension built via Xcode and embedded in the Tauri app bundle so macOS recognizes it as a valid, signed extension.

**Architecture:** A `project.yml` (xcodegen spec) defines the extension target. The build script runs `xcodegen generate` then `xcodebuild` to produce a signed `.appex`. A post-build script embeds it into the Tauri-produced `.app` bundle's `Contents/PlugIns/` and re-signs the outer app. Bundle IDs are updated from `streamcloned` to `nimbus` throughout.

**Tech Stack:** xcodegen (already installed at `/opt/homebrew/bin/xcodegen`), Xcode 26.4, xcodebuild, codesign, Tauri build hooks, Swift (FileProvider framework), Bash

---

## File Map

| Action | File | Responsibility |
|--------|------|----------------|
| Create | `src-tauri/FileProviderExtension/project.yml` | xcodegen spec for the extension target |
| Create | `src-tauri/scripts/embed-extension.sh` | Post-build: copy .appex into app bundle, re-sign |
| Modify | `src-tauri/build-extension.sh` | Rewrite: xcodegen + xcodebuild + swiftc for domain manager |
| Modify | `src-tauri/tauri.conf.json` | Update bundle config, add build hooks |
| Modify | `src-tauri/FileProviderExtension/Info.plist` | Update bundle ID to nimbus |
| Modify | `src-tauri/FileProviderExtension/FileProviderExtension.entitlements` | Update app group to nimbus |
| Modify | `src-tauri/Entitlements.plist` | Update app group to nimbus |
| Modify | `src-tauri/FileProviderExtension/SharedState.swift` | Update app group identifier |
| Modify | `src-tauri/FileProviderExtension/FileProviderExtension.swift` | Update logger subsystem |
| Modify | `src-tauri/src/commands/file_provider.rs` | Update APP_GROUP_ID constant |

---

### Task 1: Update all bundle identifiers from streamcloned to nimbus

**Files:**
- Modify: `src-tauri/tauri.conf.json`
- Modify: `src-tauri/FileProviderExtension/Info.plist`
- Modify: `src-tauri/FileProviderExtension/FileProviderExtension.entitlements`
- Modify: `src-tauri/Entitlements.plist`
- Modify: `src-tauri/FileProviderExtension/SharedState.swift`
- Modify: `src-tauri/FileProviderExtension/FileProviderExtension.swift`
- Modify: `src-tauri/src/commands/file_provider.rs`

- [ ] **Step 1: Update tauri.conf.json**

Change the identifier and product name:

```json
"productName": "Nimbus",
"identifier": "com.nimbus.app",
```

And the window title:

```json
"title": "Nimbus",
```

- [ ] **Step 2: Update Info.plist**

Replace `com.streamcloned.app` with `com.nimbus.app` in two places:

```xml
<key>CFBundleDisplayName</key>
<string>Nimbus File Provider</string>
<key>CFBundleIdentifier</key>
<string>com.nimbus.app.FileProvider</string>
```

And the document group:

```xml
<key>NSExtensionFileProviderDocumentGroup</key>
<string>group.com.nimbus.app</string>
```

- [ ] **Step 3: Update FileProviderExtension.entitlements**

Replace the app group:

```xml
<key>com.apple.security.application-groups</key>
<array>
    <string>group.com.nimbus.app</string>
</array>
```

- [ ] **Step 4: Update Entitlements.plist (main app)**

Replace the app group:

```xml
<key>com.apple.security.application-groups</key>
<array>
    <string>group.com.nimbus.app</string>
</array>
```

- [ ] **Step 5: Update SharedState.swift**

Change line 11:

```swift
static let appGroupIdentifier = "group.com.nimbus.app"
```

And the logger on line 4:

```swift
private let sharedStateLogger = Logger(subsystem: "com.nimbus.app.FileProvider", category: "shared-state")
```

- [ ] **Step 6: Update FileProviderExtension.swift**

Change line 4:

```swift
let logger = Logger(subsystem: "com.nimbus.app.FileProvider", category: "extension")
```

- [ ] **Step 7: Update file_provider.rs**

Change line 8:

```rust
const APP_GROUP_ID: &str = "group.com.nimbus.app";
```

- [ ] **Step 8: Verify Rust compiles**

Run: `cd src-tauri && cargo check 2>&1 | tail -5`
Expected: No errors

- [ ] **Step 9: Commit**

```bash
git add src-tauri/tauri.conf.json src-tauri/FileProviderExtension/Info.plist \
  src-tauri/FileProviderExtension/FileProviderExtension.entitlements \
  src-tauri/Entitlements.plist src-tauri/FileProviderExtension/SharedState.swift \
  src-tauri/FileProviderExtension/FileProviderExtension.swift \
  src-tauri/src/commands/file_provider.rs
git commit -m "chore: update bundle IDs from streamcloned to nimbus"
```

---

### Task 2: Create xcodegen project spec

**Files:**
- Create: `src-tauri/FileProviderExtension/project.yml`

- [ ] **Step 1: Create the xcodegen spec**

```yaml
name: FileProviderExtension
options:
  deploymentTarget:
    macOS: "13.0"
  bundleIdPrefix: com.nimbus.app

targets:
  FileProviderExtension:
    type: app-extension
    platform: macOS
    sources:
      - path: FileProviderExtension.swift
      - path: FileProviderItem.swift
      - path: FileProviderEnumerator.swift
      - path: RcloneClient.swift
      - path: SharedState.swift
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.nimbus.app.FileProvider
        PRODUCT_NAME: FileProviderExtension
        INFOPLIST_FILE: Info.plist
        CODE_SIGN_ENTITLEMENTS: FileProviderExtension.entitlements
        CODE_SIGN_STYLE: Automatic
        DEVELOPMENT_TEAM: 53MUTM55LC
        SWIFT_VERSION: "6.0"
        MACOSX_DEPLOYMENT_TARGET: "13.0"
        SKIP_INSTALL: "YES"
        LD_RUNPATH_SEARCH_PATHS:
          - "$(inherited)"
          - "@executable_path/../Frameworks"
          - "@executable_path/../../../../Frameworks"
    dependencies: []
```

Note: `DEVELOPMENT_TEAM: 53MUTM55LC` matches the "Developer ID Application" identity found on this machine. `CODE_SIGN_STYLE: Automatic` lets Xcode manage provisioning profiles.

- [ ] **Step 2: Verify xcodegen generates the project**

Run from the FileProviderExtension directory:

```bash
cd src-tauri/FileProviderExtension && xcodegen generate 2>&1
```

Expected: `⚙ Generating plists...` and `Created project at ...FileProviderExtension.xcodeproj`

- [ ] **Step 3: Add .xcodeproj to .gitignore**

The project is generated from `project.yml` — don't commit it. Add to the repo root `.gitignore`:

```
src-tauri/FileProviderExtension/FileProviderExtension.xcodeproj/
```

- [ ] **Step 4: Verify xcodebuild works**

```bash
cd src-tauri/FileProviderExtension && xcodebuild \
  -project FileProviderExtension.xcodeproj \
  -scheme FileProviderExtension \
  -configuration Debug \
  -derivedDataPath ../target/extension-build \
  CODE_SIGN_IDENTITY="-" \
  2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add src-tauri/FileProviderExtension/project.yml .gitignore
git commit -m "feat(fileprovider): add xcodegen project spec for extension target"
```

---

### Task 3: Rewrite build-extension.sh

**Files:**
- Modify: `src-tauri/build-extension.sh`

- [ ] **Step 1: Replace the entire script**

```bash
#!/bin/bash
set -euo pipefail

# Build the File Provider extension and domain manager CLI
# Called as Tauri's beforeBuildCommand (after frontend build)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXT_DIR="$SCRIPT_DIR/FileProviderExtension"
BUILD_DIR="$SCRIPT_DIR/target/extension"
DERIVED_DATA="$SCRIPT_DIR/target/extension-build"

# Only build on macOS
if [[ "$(uname)" != "Darwin" ]]; then
    echo "Skipping File Provider extension build (not macOS)"
    exit 0
fi

# Determine build configuration
CONFIGURATION="Debug"
CODESIGN_IDENTITY="-"  # Ad-hoc for dev
if [[ "${1:-}" == "--release" ]]; then
    CONFIGURATION="Release"
    CODESIGN_IDENTITY="Developer ID Application: Jonathan Vargas (53MUTM55LC)"
fi

echo "Building File Provider extension ($CONFIGURATION)..."
mkdir -p "$BUILD_DIR"

# Step 1: Generate Xcode project from project.yml
echo "Generating Xcode project..."
(cd "$EXT_DIR" && xcodegen generate --quiet)

# Step 2: Build extension with xcodebuild
echo "Building extension with xcodebuild..."
xcodebuild \
    -project "$EXT_DIR/FileProviderExtension.xcodeproj" \
    -scheme FileProviderExtension \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGN_IDENTITY="$CODESIGN_IDENTITY" \
    -quiet

# Step 3: Copy the built .appex to our target directory
APPEX_SRC=$(find "$DERIVED_DATA" -name "FileProviderExtension.appex" -type d | head -1)
if [[ -z "$APPEX_SRC" ]]; then
    echo "ERROR: FileProviderExtension.appex not found in build output"
    exit 1
fi

rm -rf "$BUILD_DIR/FileProviderExtension.appex"
cp -R "$APPEX_SRC" "$BUILD_DIR/"
echo "Extension built: $BUILD_DIR/FileProviderExtension.appex"

# Step 4: Build domain manager CLI (standalone, not part of Xcode project)
echo "Building domain manager CLI..."
swiftc \
    -target arm64-apple-macos13.0 \
    -sdk "$(xcrun --show-sdk-path)" \
    -framework Foundation \
    -framework FileProvider \
    -module-name DomainManager \
    -parse-as-library \
    -emit-executable \
    -o "$BUILD_DIR/fp-domain-manager" \
    "$EXT_DIR/DomainManager.swift"

# Sign the domain manager
codesign --force --sign "$CODESIGN_IDENTITY" "$BUILD_DIR/fp-domain-manager"

echo "Domain manager CLI built: $BUILD_DIR/fp-domain-manager"
echo "File Provider build complete."
```

- [ ] **Step 2: Make it executable and verify**

```bash
chmod +x src-tauri/build-extension.sh
src-tauri/build-extension.sh 2>&1 | tail -5
```

Expected: `File Provider build complete.`

- [ ] **Step 3: Verify the outputs exist**

```bash
ls -la src-tauri/target/extension/FileProviderExtension.appex/Contents/MacOS/
ls -la src-tauri/target/extension/fp-domain-manager
```

Expected: Both binaries exist

- [ ] **Step 4: Commit**

```bash
git add src-tauri/build-extension.sh
git commit -m "feat(fileprovider): rewrite build script to use xcodegen + xcodebuild"
```

---

### Task 4: Create the embed-extension.sh post-build script

**Files:**
- Create: `src-tauri/scripts/embed-extension.sh`

- [ ] **Step 1: Create the scripts directory and script**

```bash
#!/bin/bash
set -euo pipefail

# Embed the File Provider extension into the Tauri app bundle
# Called after `cargo tauri build` produces the .app

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TAURI_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$TAURI_DIR/target/extension"

# Only run on macOS
if [[ "$(uname)" != "Darwin" ]]; then
    exit 0
fi

# Find the built .app bundle
# In dev mode, the binary runs directly (no .app bundle to embed into)
# In build mode, it's in target/release/bundle/macos/
APP_BUNDLE=$(find "$TAURI_DIR/target/release/bundle/macos" -name "*.app" -maxdepth 1 2>/dev/null | head -1)

if [[ -z "$APP_BUNDLE" ]]; then
    echo "No .app bundle found — skipping extension embedding (dev mode?)"
    exit 0
fi

echo "Embedding File Provider extension into: $APP_BUNDLE"

APPEX_SRC="$BUILD_DIR/FileProviderExtension.appex"
DOMAIN_MGR_SRC="$BUILD_DIR/fp-domain-manager"

if [[ ! -d "$APPEX_SRC" ]]; then
    echo "ERROR: FileProviderExtension.appex not found at $APPEX_SRC"
    echo "Run build-extension.sh first."
    exit 1
fi

if [[ ! -f "$DOMAIN_MGR_SRC" ]]; then
    echo "ERROR: fp-domain-manager not found at $DOMAIN_MGR_SRC"
    exit 1
fi

# Create PlugIns directory and copy the extension
PLUGINS_DIR="$APP_BUNDLE/Contents/PlugIns"
mkdir -p "$PLUGINS_DIR"
rm -rf "$PLUGINS_DIR/FileProviderExtension.appex"
cp -R "$APPEX_SRC" "$PLUGINS_DIR/"
echo "Copied FileProviderExtension.appex to PlugIns/"

# Copy domain manager into MacOS/
cp "$DOMAIN_MGR_SRC" "$APP_BUNDLE/Contents/MacOS/"
echo "Copied fp-domain-manager to MacOS/"

# Determine signing identity
CODESIGN_IDENTITY="-"
if [[ "${1:-}" == "--release" ]]; then
    CODESIGN_IDENTITY="Developer ID Application: Jonathan Vargas (53MUTM55LC)"
fi

# Re-sign the entire app bundle (required after adding nested bundles)
echo "Re-signing app bundle..."
codesign --force --deep --sign "$CODESIGN_IDENTITY" "$APP_BUNDLE"

# Verify
echo "Verifying signature..."
codesign --verify --deep --strict "$APP_BUNDLE" 2>&1 && echo "Signature valid." || echo "WARNING: Signature verification failed"

echo "Extension embedding complete."
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x src-tauri/scripts/embed-extension.sh
```

- [ ] **Step 3: Commit**

```bash
git add src-tauri/scripts/embed-extension.sh
git commit -m "feat(fileprovider): add post-build script to embed extension in app bundle"
```

---

### Task 5: Wire build hooks into Tauri config

**Files:**
- Modify: `src-tauri/tauri.conf.json`

- [ ] **Step 1: Update the build commands in tauri.conf.json**

The `beforeBuildCommand` needs to run both the frontend build AND the extension build. Update the `build` section:

```json
"build": {
    "beforeDevCommand": "npm run dev",
    "devUrl": "http://localhost:1420",
    "beforeBuildCommand": "npm run build && cd src-tauri && bash build-extension.sh --release",
    "frontendDist": "../dist"
}
```

Note: For dev mode, the extension needs to be built separately (run `src-tauri/build-extension.sh` manually or add it to the dev workflow). The `beforeDevCommand` is `npm run dev` (Vite dev server) and shouldn't block on the extension build. Developers should run `build-extension.sh` once before `cargo tauri dev`.

- [ ] **Step 2: Verify the config is valid JSON**

```bash
python3 -c "import json; json.load(open('src-tauri/tauri.conf.json'))" && echo "Valid JSON"
```

Expected: `Valid JSON`

- [ ] **Step 3: Commit**

```bash
git add src-tauri/tauri.conf.json
git commit -m "feat(fileprovider): wire extension build into Tauri beforeBuildCommand"
```

---

### Task 6: End-to-end verification

- [ ] **Step 1: Clean build the extension**

```bash
rm -rf src-tauri/target/extension src-tauri/target/extension-build
src-tauri/build-extension.sh 2>&1
```

Expected: `File Provider build complete.`

- [ ] **Step 2: Verify .appex bundle structure**

```bash
ls src-tauri/target/extension/FileProviderExtension.appex/Contents/
ls src-tauri/target/extension/FileProviderExtension.appex/Contents/MacOS/
cat src-tauri/target/extension/FileProviderExtension.appex/Contents/Info.plist | grep -A1 CFBundleIdentifier
```

Expected:
- `Contents/` has `Info.plist` and `MacOS/`
- `MacOS/` has the `FileProviderExtension` binary
- Bundle ID shows `com.nimbus.app.FileProvider`

- [ ] **Step 3: Verify code signing of the .appex**

```bash
codesign --verify --deep --strict src-tauri/target/extension/FileProviderExtension.appex 2>&1
```

Expected: No errors (clean verification)

- [ ] **Step 4: Verify domain manager still works**

```bash
src-tauri/target/extension/fp-domain-manager list 2>&1
```

Expected: Either `No File Provider domains registered` or a list of existing domains

- [ ] **Step 5: Build the full Tauri app (release)**

```bash
cargo tauri build 2>&1 | tail -20
```

Expected: Build succeeds. Note the path of the produced `.app` bundle.

- [ ] **Step 6: Embed the extension**

```bash
src-tauri/scripts/embed-extension.sh --release 2>&1
```

Expected: `Extension embedding complete.`

- [ ] **Step 7: Verify the final app bundle**

```bash
APP=$(find src-tauri/target/release/bundle/macos -name "*.app" -maxdepth 1 | head -1)
ls "$APP/Contents/PlugIns/"
ls "$APP/Contents/MacOS/fp-domain-manager"
codesign --verify --deep --strict "$APP" 2>&1
```

Expected:
- `PlugIns/` contains `FileProviderExtension.appex`
- `fp-domain-manager` exists in `MacOS/`
- Signature verification passes

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat(fileprovider): verified end-to-end extension build and bundle embedding"
```
