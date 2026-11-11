#!/usr/bin/env bash
# Build-time check: fail if Package.resolved pins any remote package other
# than Sparkle (the updater, #100). RcloneKit is local and never appears here.
#
#   bash scripts/lint-package-resolved.sh [path/to/Package.resolved]

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESOLVED="${1:-$ROOT_DIR/Nimbus/Nimbus.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved}"

if [ ! -f "$RESOLVED" ]; then
  echo "lint-package-resolved: no Package.resolved (no remote SPM deps) — OK"
  exit 0
fi

# One line per pin: "<identity> <location>".
pins="$(/usr/bin/python3 -c '
import json, sys
for pin in json.load(open(sys.argv[1])).get("pins", []):
    print(pin.get("identity", ""), pin.get("location", ""))
' "$RESOLVED")"

status=0
while read -r identity location; do
  [ -z "$identity" ] && continue
  location="${location%.git}"
  if [ "$identity" != "sparkle" ] || [ "$location" != "https://github.com/sparkle-project/Sparkle" ]; then
    echo "error: remote SPM dependency '$identity' ($location) is forbidden. Allowed: Sparkle only." >&2
    status=1
  fi
done <<< "$pins"

[ "$status" -eq 0 ] && echo "lint-package-resolved: OK"
exit "$status"
