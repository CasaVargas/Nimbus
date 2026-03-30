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

# Strip extended attributes that prevent codesigning
echo "Stripping extended attributes..."
xattr -cr "$APP_BUNDLE"

# Re-sign the entire app bundle (required after adding nested bundles)
echo "Re-signing app bundle..."
codesign --force --deep --sign "$CODESIGN_IDENTITY" "$APP_BUNDLE"

# Verify
echo "Verifying signature..."
codesign --verify --deep --strict "$APP_BUNDLE" 2>&1 && echo "Signature valid." || echo "WARNING: Signature verification failed"

echo "Extension embedding complete."
