#!/usr/bin/env bash
# Every release's notes end with the Beltr / OneScribe footer
# (docs/releases/FOOTER.md), with the Beltr link tagged for that version.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
status=0
for file in "$ROOT_DIR"/docs/releases/[0-9]*.md; do
  version="$(basename "$file" .md)"
  if ! grep -q "utm_medium=release-notes&utm_campaign=nimbus&utm_content=$version)" "$file" \
     || ! grep -q "apps.apple.com/us/app/onescribe-ai-note-scanner/id6756506734" "$file"; then
    echo "error: docs/releases/$version.md is missing the footer from docs/releases/FOOTER.md (utm_content=$version)" >&2
    status=1
  fi
done
[ "$status" -eq 0 ] && echo "lint-release-notes: OK"
exit "$status"
