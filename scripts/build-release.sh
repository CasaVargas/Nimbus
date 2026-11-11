#!/usr/bin/env bash
# Builds the Nimbus SwiftUI app for release.
# Tauri build is end-of-life; see DEPRECATED.md and legacy/tauri/.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../Nimbus" && pwd)"
cd "$PROJECT_DIR"

echo "==> Regenerating Xcode project from project.yml"
xcodegen generate

# Always start from clean Release products. The packager used to re-sign the
# app in place here, and an incremental rebuild then embedded a Developer ID
# signed extension inside an Apple Development signed app and failed with
# "Embedded binary is not signed with the same certificate as the parent app".
rm -rf build/Build/Products/Release

# NIMBUS_UNSIGNED_BUILD=1 builds without signing (CI has no Apple
# Development certificate). package-release.sh then signs with Developer ID
# using the checked-in .entitlements files.
UNSIGNED_ARGS=()
if [ "${NIMBUS_UNSIGNED_BUILD:-0}" = "1" ]; then
  UNSIGNED_ARGS=(CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO)
fi

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
  ${UNSIGNED_ARGS[@]+"${UNSIGNED_ARGS[@]}"} \
  build

echo "==> Release build complete: build/Build/Products/Release/Nimbus.app"
