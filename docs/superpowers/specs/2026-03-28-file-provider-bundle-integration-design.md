# File Provider Bundle Integration — Design Spec

**Goal:** Get the Apple File Provider extension built via Xcode and embedded in the Tauri app bundle so macOS recognizes it as a valid extension.

**Parent initiative:** Nimbus premium v1 launch — File Provider sub-project 1 of 6

---

## Scope

### In scope
1. Minimal Xcode project for the File Provider extension target (no app target)
2. Build script that runs `xcodebuild` to compile and sign the extension
3. Post-build script that copies the signed `.appex` into `Contents/PlugIns/` and re-signs the outer app
4. Tauri build hooks to automate the above
5. Works for both `cargo tauri dev` and `cargo tauri build`
6. Update bundle IDs and app group identifiers from `streamcloned` to `nimbus`

### Out of scope
- Domain registration wiring (sub-project 2)
- Change tracking (sub-project 3)
- Mount lifecycle UI (sub-project 4)
- Error recovery (sub-project 5)
- Thumbnails & metadata (sub-project 6)

---

## Architecture

### Xcode project

A new `FileProviderExtension.xcodeproj` in `src-tauri/FileProviderExtension/` with one target: the `.appex` extension. No app target — the main app is Tauri-built. The project references the existing Swift source files already in that directory:

- `FileProviderExtension.swift`
- `FileProviderItem.swift`
- `FileProviderEnumerator.swift`
- `RcloneClient.swift`
- `SharedState.swift`

The `DomainManager.swift` stays as a separate CLI tool compiled by the build script (not part of the Xcode project — it's a standalone binary, not an extension component).

### Build flow

```
cargo tauri build (or cargo tauri dev)
  → beforeBuildCommand: src-tauri/build-extension.sh
    → xcodebuild -project FileProviderExtension.xcodeproj \
        -scheme FileProviderExtension \
        -configuration [Debug|Release] \
        -derivedDataPath build/
    → Compiles DomainManager.swift into fp-domain-manager via swiftc (kept from old script)
    → Produces signed .appex + fp-domain-manager binary
  → Tauri builds the Rust + frontend as normal
  → Tauri produces .app bundle
  → Post-build: src-tauri/scripts/embed-extension.sh
    → Copies .appex into <app>.app/Contents/PlugIns/
    → Copies fp-domain-manager into <app>.app/Contents/MacOS/
    → Re-signs the outer app bundle with --deep
```

### Bundle identifiers

| Component | Old | New |
|-----------|-----|-----|
| Main app | `com.streamcloned.app` | `com.nimbus.app` |
| Extension | `com.streamcloned.app.FileProvider` | `com.nimbus.app.FileProvider` |
| App Group | `group.com.streamcloned.app` | `group.com.nimbus.app` |

### Code signing

- Extension signed with developer identity during `xcodebuild` (Xcode handles this via the project's signing settings)
- `fp-domain-manager` signed with `codesign --force --sign -` (ad-hoc, it's a helper binary)
- Outer app re-signed after embedding the plugin — required because adding a nested bundle invalidates the parent signature
- For dev builds (`cargo tauri dev`), ad-hoc signing is sufficient
- For distribution builds, the full developer identity is used

### Dev mode considerations

`cargo tauri dev` uses `beforeDevCommand` (npm run dev) and runs the Rust binary directly. The extension needs to be built and available for the domain manager to register domains. The build script detects dev vs release mode and adjusts:
- Dev: builds with `-configuration Debug`, ad-hoc signs
- Release: builds with `-configuration Release`, identity signs

---

## File Changes

### New files

- **`src-tauri/FileProviderExtension/FileProviderExtension.xcodeproj/`** — Xcode project with one extension target. References existing Swift files. Signing configured for the developer's team. Deployment target macOS 13.0 (minimum for NSFileProviderReplicatedExtension).

- **`src-tauri/scripts/embed-extension.sh`** — Post-build script:
  - Finds the built `.app` bundle in Tauri's target directory
  - Creates `Contents/PlugIns/` if it doesn't exist
  - Copies `FileProviderExtension.appex` into it
  - Copies `fp-domain-manager` into `Contents/MacOS/`
  - Re-signs the app bundle with `codesign --force --deep --sign`

### Modified files

- **`src-tauri/build-extension.sh`** — Rewrite to:
  - Call `xcodebuild` for the extension instead of raw `swiftc`
  - Keep the `swiftc` compilation of `DomainManager.swift` into `fp-domain-manager`
  - Accept a `--release` flag to switch between Debug/Release configurations
  - Output binaries to a predictable location (`src-tauri/target/extension/`)

- **`src-tauri/tauri.conf.json`** — Add/update `beforeBuildCommand` to run `build-extension.sh`. The `afterBuildCommand` or a Tauri plugin hook runs `embed-extension.sh`.

- **`src-tauri/FileProviderExtension/Info.plist`** — Update `CFBundleIdentifier` to `com.nimbus.app.FileProvider`

- **`src-tauri/FileProviderExtension/FileProviderExtension.entitlements`** — Update `com.apple.security.application-groups` to `["group.com.nimbus.app"]`

- **`src-tauri/Entitlements.plist`** — Update `com.apple.security.application-groups` to `["group.com.nimbus.app"]`

- **`src-tauri/FileProviderExtension/SharedState.swift`** — Update the app group identifier constant from `group.com.streamcloned.app` to `group.com.nimbus.app`

---

## Verification

The implementation is complete when:

1. `cargo tauri build` produces a `.app` bundle
2. The bundle contains `Contents/PlugIns/FileProviderExtension.appex`
3. The bundle contains `Contents/MacOS/fp-domain-manager`
4. `codesign --verify --deep --strict <app>` passes
5. Running the app and calling `fp-domain-manager list` from the embedded binary works
6. `cargo tauri dev` also builds the extension and the domain manager is callable
