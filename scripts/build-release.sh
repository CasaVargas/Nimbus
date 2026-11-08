#!/usr/bin/env bash
# Builds the Nimbus SwiftUI app for release.
# Tauri build is end-of-life; see DEPRECATED.md and legacy/tauri/.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../Nimbus" && pwd)"
cd "$PROJECT_DIR"

echo "==> Regenerating Xcode project from project.yml"
xcodegen generate

echo "==> Building Nimbus (Release)"
# CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO keeps Xcode from adding the
# get-task-allow debugging entitlement that a plain `build` (as opposed to an
# archive) injects. The notary service rejects any executable that has it.
xcodebuild \
  -scheme Nimbus \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath build \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  build

echo "==> Release build complete: build/Build/Products/Release/Nimbus.app"
