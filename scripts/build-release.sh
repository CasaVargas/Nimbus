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
# Build .app only — DMG must be created after extension embedding (step 4)
cargo tauri build --bundles app

echo "=== Step 4/4: Embedding extension into app bundle ==="
bash src-tauri/scripts/embed-extension.sh --release

echo ""
echo "=== Release build complete ==="
echo "App bundle: src-tauri/target/release/bundle/macos/Nimbus.app"
