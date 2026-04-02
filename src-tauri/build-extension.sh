#!/bin/bash
set -euo pipefail

# Build the File Provider extension using swiftc
# This script is called from the Tauri build process

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXT_DIR="$SCRIPT_DIR/FileProviderExtension"
BUILD_DIR="$SCRIPT_DIR/target/extension"

# Only build on macOS
if [[ "$(uname)" != "Darwin" ]]; then
    echo "Skipping File Provider extension build (not macOS)"
    exit 0
fi

echo "Building File Provider extension..."

mkdir -p "$BUILD_DIR"

# Compile all Swift sources into the extension binary
SWIFT_FILES=(
    "$EXT_DIR/FileProviderExtension.swift"
    "$EXT_DIR/FileProviderItem.swift"
    "$EXT_DIR/FileProviderEnumerator.swift"
    "$EXT_DIR/RcloneClient.swift"
    "$EXT_DIR/SharedState.swift"
)

# Check if source files exist
for f in "${SWIFT_FILES[@]}"; do
    if [[ ! -f "$f" ]]; then
        echo "ERROR: Missing source file: $f"
        exit 1
    fi
done

swiftc \
    -target arm64-apple-macos12.0 \
    -sdk "$(xcrun --show-sdk-path)" \
    -framework Foundation \
    -framework FileProvider \
    -framework UniformTypeIdentifiers \
    -module-name FileProviderExtension \
    -emit-library \
    -o "$BUILD_DIR/FileProviderExtension" \
    "${SWIFT_FILES[@]}"

echo "File Provider extension built: $BUILD_DIR/FileProviderExtension"

# Create the .appex bundle structure
APPEX_DIR="$BUILD_DIR/FileProviderExtension.appex"
rm -rf "$APPEX_DIR"
mkdir -p "$APPEX_DIR/Contents/MacOS"

cp "$BUILD_DIR/FileProviderExtension" "$APPEX_DIR/Contents/MacOS/"
cp "$EXT_DIR/Info.plist" "$APPEX_DIR/Contents/"

echo "File Provider extension bundle created: $APPEX_DIR"

# Build the domain manager CLI tool
echo "Building domain manager CLI..."

swiftc \
    -target arm64-apple-macos12.0 \
    -sdk "$(xcrun --show-sdk-path)" \
    -framework Foundation \
    -framework FileProvider \
    -module-name DomainManager \
    -parse-as-library \
    -emit-executable \
    -o "$BUILD_DIR/fp-domain-manager" \
    "$EXT_DIR/DomainManager.swift"

echo "Domain manager CLI built: $BUILD_DIR/fp-domain-manager"
