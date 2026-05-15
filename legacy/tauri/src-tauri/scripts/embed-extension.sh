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

APP_NAME="$(basename "$APP_BUNDLE")"

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

# Copy the .app to /tmp for signing — iCloud/File Provider adds xattrs to files
# on synced drives that codesign rejects and that can't be permanently stripped.
SIGN_DIR=$(mktemp -d -t nimbus-sign)
trap 'rm -rf "$SIGN_DIR"' EXIT

echo "Copying to temp directory for signing (avoids iCloud xattr interference)..."
cp -R "$APP_BUNDLE" "$SIGN_DIR/"
SIGN_BUNDLE="$SIGN_DIR/$APP_NAME"

# Create PlugIns directory and copy the extension
PLUGINS_DIR="$SIGN_BUNDLE/Contents/PlugIns"
mkdir -p "$PLUGINS_DIR"
rm -rf "$PLUGINS_DIR/FileProviderExtension.appex"
cp -R "$APPEX_SRC" "$PLUGINS_DIR/"
echo "Copied FileProviderExtension.appex to PlugIns/"

# Copy domain manager into MacOS/
cp "$DOMAIN_MGR_SRC" "$SIGN_BUNDLE/Contents/MacOS/"
echo "Copied fp-domain-manager to MacOS/"

# Determine signing identity
CODESIGN_IDENTITY="-"
if [[ "${1:-}" == "--release" ]]; then
    CODESIGN_IDENTITY="Developer ID Application: Jonathan Vargas (53MUTM55LC)"
fi

# Strip any residual extended attributes
echo "Stripping extended attributes..."
xattr -cr "$SIGN_BUNDLE"

# Sign inner components first with their own entitlements, then the outer app.
# --deep would re-sign the .appex without its entitlements, breaking Gatekeeper.
ENTITLEMENTS_DIR="$TAURI_DIR/FileProviderExtension"

echo "Signing extension..."
codesign --force --sign "$CODESIGN_IDENTITY" \
    --entitlements "$ENTITLEMENTS_DIR/FileProviderExtension.entitlements" \
    "$PLUGINS_DIR/FileProviderExtension.appex"

echo "Signing domain manager..."
codesign --force --sign "$CODESIGN_IDENTITY" \
    "$SIGN_BUNDLE/Contents/MacOS/fp-domain-manager"

echo "Signing app bundle..."
codesign --force --sign "$CODESIGN_IDENTITY" \
    --entitlements "$TAURI_DIR/Entitlements.plist" \
    "$SIGN_BUNDLE"

# Verify
echo "Verifying signature..."
codesign --verify --deep --strict "$SIGN_BUNDLE" 2>&1 && echo "Signature valid." || {
    echo "ERROR: Signature verification failed"
    exit 1
}

# Copy signed bundle back to original location
echo "Copying signed bundle back..."
rm -rf "$APP_BUNDLE"
cp -R "$SIGN_BUNDLE" "$APP_BUNDLE"

echo "Extension embedding complete."
echo "Signed app: $APP_BUNDLE"
