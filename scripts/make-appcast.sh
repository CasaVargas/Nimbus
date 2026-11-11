#!/usr/bin/env bash
# Writes the Sparkle appcast for one release (#100).
#
#   NIMBUS_SPARKLE_KEY=<private key> bash scripts/make-appcast.sh <dmg> <version> <min-macos> [out.xml]
#
# The appcast has one item: this release, its DMG as the enclosure, signed
# with the EdDSA key the app trusts (SUPublicEDKey). It is uploaded to the
# GitHub release as appcast.xml; the app's feed URL is
# releases/latest/download/appcast.xml, so publishing the release ships the
# update. Sign the final DMG: run this after notarizing and stapling.
#
# Environment:
#   NIMBUS_SPARKLE_KEY   the private key, as `generate_keys -x` exports it
#   NIMBUS_SPARKLE_BIN   folder holding Sparkle's sign_update (default: the
#                        package's artefacts under Nimbus/build)

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DMG="${1:?usage: make-appcast.sh <dmg> <version> <min-macos> [out.xml]}"
VERSION="${2:?version missing}"
MIN_OS="${3:?minimum macOS version missing}"
OUT="${4:-$(dirname "$DMG")/appcast.xml}"
SPARKLE_BIN="${NIMBUS_SPARKLE_BIN:-$ROOT_DIR/Nimbus/build/SourcePackages/artifacts/sparkle/Sparkle/bin}"
NOTES="$ROOT_DIR/docs/releases/$VERSION.md"

if [ -z "${NIMBUS_SPARKLE_KEY:-}" ]; then
  echo "error: NIMBUS_SPARKLE_KEY is not set" >&2
  exit 1
fi
if [ ! -x "$SPARKLE_BIN/sign_update" ]; then
  echo "error: $SPARKLE_BIN/sign_update not found. Build first, or set NIMBUS_SPARKLE_BIN." >&2
  exit 1
fi
test -f "$DMG" || { echo "error: $DMG not found" >&2; exit 1; }
test -f "$NOTES" || { echo "error: $NOTES not found" >&2; exit 1; }

SIGNATURE="$(printf '%s' "$NIMBUS_SPARKLE_KEY" | "$SPARKLE_BIN/sign_update" --ed-key-file - -p "$DMG")"
if [ -z "$SIGNATURE" ]; then
  echo "error: sign_update produced no signature" >&2
  exit 1
fi

DMG="$DMG" VERSION="$VERSION" MIN_OS="$MIN_OS" OUT="$OUT" NOTES="$NOTES" SIGNATURE="$SIGNATURE" \
/usr/bin/python3 - <<'PY'
import hashlib, os
from email.utils import formatdate
from xml.sax.saxutils import escape, quoteattr

dmg, version, out = os.environ["DMG"], os.environ["VERSION"], os.environ["OUT"]
name = os.path.basename(dmg)
data = open(dmg, "rb").read()

# Sparkle wants major.minor.patch.
min_os = (os.environ["MIN_OS"].split(".") + ["0", "0"])[:3]

notes = open(os.environ["NOTES"], encoding="utf-8").read()
notes = notes.replace("(filled in when the signed DMG is built)", hashlib.sha256(data).hexdigest())
notes = notes.replace("]]>", "]]]]><![CDATA[>")

url = f"https://github.com/CasaVargas/Nimbus/releases/download/v{version}/{name}"
xml = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Nimbus</title>
    <link>https://github.com/CasaVargas/Nimbus/releases</link>
    <item>
      <title>Nimbus {escape(version)}</title>
      <link>https://github.com/CasaVargas/Nimbus/releases/tag/v{escape(version)}</link>
      <pubDate>{formatdate(usegmt=True)}</pubDate>
      <sparkle:version>{escape(version)}</sparkle:version>
      <sparkle:shortVersionString>{escape(version)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{escape(".".join(min_os))}</sparkle:minimumSystemVersion>
      <description sparkle:format="markdown"><![CDATA[{notes}]]></description>
      <enclosure url={quoteattr(url)} sparkle:edSignature={quoteattr(os.environ["SIGNATURE"])} length="{len(data)}" type="application/octet-stream"/>
    </item>
  </channel>
</rss>
"""
open(out, "w", encoding="utf-8").write(xml)
PY

echo "==> Wrote $OUT (Nimbus $VERSION, $(basename "$DMG"))"
