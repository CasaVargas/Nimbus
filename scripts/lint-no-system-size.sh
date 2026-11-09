#!/usr/bin/env bash
# Build-time check: fail if any Swift source under Nimbus/ or RcloneKit/Sources/
# uses `.system(size:)`. Semantic font helpers only.
#
# The token files under Nimbus/Nimbus/DesignSystem are exempt: that is where
# the semantic helpers are defined, and display sizes such as the 52 pt hero
# have no system text style to build on.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

matches=$(grep -rnE '\.system\(size:' \
  "$ROOT_DIR/Nimbus/Nimbus" \
  "$ROOT_DIR/RcloneKit/Sources" \
  --include='*.swift' \
  --exclude-dir='DesignSystem' || true)

if [ -n "$matches" ]; then
  echo "error: .system(size:) is forbidden — use DesignSystem.Typography semantic helpers." >&2
  echo "$matches" >&2
  exit 1
fi

echo "lint-no-system-size: OK"
