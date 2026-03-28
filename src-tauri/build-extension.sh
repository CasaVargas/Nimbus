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
