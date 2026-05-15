#!/usr/bin/env bash
# Build-time check: fail if Package.resolved adds any UI dependency.
# Allowed: only the local RcloneKit package (which never appears in Package.resolved).

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESOLVED="$ROOT_DIR/Nimbus/Nimbus.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"

if [ ! -f "$RESOLVED" ]; then
  echo "lint-package-resolved: no Package.resolved (no remote SPM deps) — OK"
  exit 0
fi

# Any "pins" entry means a remote SPM dep was added. Fail.
if grep -q '"identity"' "$RESOLVED"; then
  echo "error: remote SPM dependencies are forbidden. Local packages only (RcloneKit)." >&2
  cat "$RESOLVED" >&2
  exit 1
fi

echo "lint-package-resolved: OK"
