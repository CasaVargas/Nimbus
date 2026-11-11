#!/usr/bin/env bash
# One-time setup of the Sparkle update-signing key (#100).
#
#   bash scripts/setup-sparkle-key.sh
#
# 1. Creates the EdDSA key in your login Keychain, or reuses the one already
#    there (one Sparkle key can serve every app).
# 2. Writes its public half to SUPublicEDKey in Nimbus/Config/Nimbus-Info.plist.
# 3. Stores the private half as the SPARKLE_PRIVATE_KEY secret of this
#    repository, through a temporary file that is deleted again.
#
# The Keychain copy is the original: back it up (`generate_keys -x <file>`
# into a password manager). Without it no update can be signed for installed
# copies. Needs a build first, for Sparkle's tools.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPARKLE_BIN="${NIMBUS_SPARKLE_BIN:-$ROOT_DIR/Nimbus/build/SourcePackages/artifacts/sparkle/Sparkle/bin}"
PLIST="$ROOT_DIR/Nimbus/Config/Nimbus-Info.plist"
REPO="${NIMBUS_REPO:-CasaVargas/Nimbus}"

if [ ! -x "$SPARKLE_BIN/generate_keys" ]; then
  echo "error: $SPARKLE_BIN/generate_keys not found. Run scripts/build-release.sh first, or set NIMBUS_SPARKLE_BIN." >&2
  exit 1
fi

if ! PUBLIC_KEY="$("$SPARKLE_BIN/generate_keys" -p 2>/dev/null)" || [ -z "$PUBLIC_KEY" ]; then
  echo "==> No Sparkle key in the Keychain; creating one"
  "$SPARKLE_BIN/generate_keys" >/dev/null
  PUBLIC_KEY="$("$SPARKLE_BIN/generate_keys" -p)"
else
  echo "==> Using the Sparkle key already in the Keychain"
fi
echo "==> Public key: $PUBLIC_KEY"

/usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $PUBLIC_KEY" "$PLIST"
echo "==> Wrote SUPublicEDKey to $PLIST"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
chmod 700 "$TMP"
"$SPARKLE_BIN/generate_keys" -x "$TMP/key" >/dev/null
gh secret set SPARKLE_PRIVATE_KEY --repo "$REPO" < "$TMP/key"
echo "==> Set the SPARKLE_PRIVATE_KEY secret on $REPO"

# Prove the secret's key and the public key are a pair: sign and verify a file.
head -c 4096 /dev/urandom > "$TMP/Nimbus-0.0.0.dmg"
SIGNATURE="$("$SPARKLE_BIN/sign_update" --ed-key-file "$TMP/key" -p "$TMP/Nimbus-0.0.0.dmg")"
cat > "$TMP/appcast.xml" <<XML
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
<enclosure url="https://example.invalid/Nimbus-0.0.0.dmg" sparkle:edSignature="$SIGNATURE" length="4096"/>
</item></channel></rss>
XML
xcrun swift "$ROOT_DIR/scripts/verify-appcast.swift" "$TMP/appcast.xml" "$TMP/Nimbus-0.0.0.dmg" "$PUBLIC_KEY"
echo "==> Done. Commit Nimbus/Config/Nimbus-Info.plist."
