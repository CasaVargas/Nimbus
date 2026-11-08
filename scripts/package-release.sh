#!/usr/bin/env bash
# Packages the Release build of Nimbus into a distributable DMG.
#
#   bash scripts/package-release.sh
#
# Steps:
#   1. Build Release via scripts/build-release.sh (skip with NIMBUS_SKIP_BUILD=1
#      if Nimbus/build/Build/Products/Release/Nimbus.app is already current).
#   2. If NIMBUS_SIGN_IDENTITY is set, re-sign the app with that Developer ID
#      identity and the hardened runtime (required for notarization).
#   3. Create dist/Nimbus-<version>.dmg with hdiutil, plus a .sha256 file.
#   4. If NIMBUS_SIGN_IDENTITY and NIMBUS_NOTARY_PROFILE are both set, sign
#      the DMG, submit it to Apple's notary service with notarytool, wait for
#      the verdict, and staple the ticket.
#
# Environment:
#   NIMBUS_SIGN_IDENTITY   e.g. "Developer ID Application: Your Name (TEAMID)"
#   NIMBUS_NOTARY_PROFILE  a keychain profile created with
#                          `xcrun notarytool store-credentials <name>`
#   NIMBUS_SKIP_BUILD=1    package the existing Release build without rebuilding
#   NIMBUS_DIST_DIR        output directory (default: <repo>/dist)
#
# Without the two signing variables the script produces an unsigned DMG that
# is fine for local testing but will be blocked by Gatekeeper on other Macs.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT_DIR/Nimbus/build/Build/Products/Release/Nimbus.app"
APPEX="$APP/Contents/PlugIns/FileProviderExtension.appex"
DIST_DIR="${NIMBUS_DIST_DIR:-$ROOT_DIR/dist}"
SIGN_IDENTITY="${NIMBUS_SIGN_IDENTITY:-}"
NOTARY_PROFILE="${NIMBUS_NOTARY_PROFILE:-}"

log() { printf '==> %s\n' "$*"; }

if [ "${NIMBUS_SKIP_BUILD:-0}" != "1" ]; then
  bash "$ROOT_DIR/scripts/build-release.sh"
fi

if [ ! -d "$APP" ]; then
  echo "error: $APP not found. Run scripts/build-release.sh first." >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
DMG="$DIST_DIR/Nimbus-$VERSION.dmg"
VOLNAME="Nimbus $VERSION"

mkdir -p "$DIST_DIR"
rm -f "$DMG" "$DMG.sha256"

if [ -n "$SIGN_IDENTITY" ]; then
  log "Signing with: $SIGN_IDENTITY"
  # Sign inside-out so the embedded extension is sealed before the app that
  # contains it. --preserve-metadata keeps the entitlements Xcode applied
  # (app group, File Provider, network); --options runtime enables the
  # hardened runtime that notarization requires.
  if [ -d "$APPEX" ]; then
    codesign --force --timestamp --options runtime \
      --preserve-metadata=entitlements,identifier \
      --sign "$SIGN_IDENTITY" "$APPEX"
  fi
  codesign --force --deep --timestamp --options runtime \
    --preserve-metadata=entitlements,identifier \
    --sign "$SIGN_IDENTITY" "$APP"
  codesign --verify --deep --strict --verbose=2 "$APP"
else
  log "NIMBUS_SIGN_IDENTITY not set; leaving the app with its build signature"
fi

log "Creating $DMG"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/nimbus-dmg.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/Nimbus.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create \
  -volname "$VOLNAME" \
  -srcfolder "$STAGE" \
  -fs HFS+ \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  "$DMG" >/dev/null

if [ -n "$SIGN_IDENTITY" ]; then
  log "Signing DMG"
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
fi

if [ -n "$SIGN_IDENTITY" ] && [ -n "$NOTARY_PROFILE" ]; then
  log "Submitting to the notary service (profile: $NOTARY_PROFILE)"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  log "Stapling ticket"
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG" || true
elif [ -n "$SIGN_IDENTITY" ]; then
  log "NIMBUS_NOTARY_PROFILE not set; DMG is signed but not notarized"
fi

(cd "$DIST_DIR" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")

log "Done: $DMG (Nimbus $VERSION, build $BUILD)"
cat "$DMG.sha256"
