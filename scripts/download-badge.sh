#!/usr/bin/env bash
# Prints a shields.io endpoint badge (JSON) with the number of DMG downloads
# across all published releases.
#
# The stock shields "downloads/total" badge is no use here: it sums every
# release asset, and Sparkle fetches appcast.xml from the latest release on
# each update check, so update checks would be counted as downloads. This
# counts the DMGs only, the same rule the website uses (site/index.html).
#
# Usage: scripts/download-badge.sh [owner/repo]   (needs gh and jq)
set -euo pipefail

repo="${1:-${GITHUB_REPOSITORY:-CasaVargas/Nimbus}}"

gh api "repos/${repo}/releases" --paginate \
  --jq '.[] | select(.draft | not) | .assets[] | select(.name | endswith(".dmg")) | .download_count' \
  | jq -sc '{schemaVersion: 1, label: "downloads", message: (add // 0 | tostring), color: "blue"}'
