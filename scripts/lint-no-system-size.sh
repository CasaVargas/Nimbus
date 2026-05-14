#!/usr/bin/env bash
# Build-time check: fail if any Swift source under Nimbus/ or RcloneKit/Sources/
# uses `.system(size:)`. Semantic font helpers only.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

matches=$(grep -rnE '\.system\(size:' \
  "$ROOT_DIR/Nimbus/Nimbus" \
  "$ROOT_DIR/RcloneKit/Sources" \
  --include='*.swift' || true)

if [ -n "$matches" ]; then
  echo "error: .system(size:) is forbidden — use DesignSystem.Typography semantic helpers." >&2
  echo "$matches" >&2
  exit 1
fi

echo "lint-no-system-size: OK"
