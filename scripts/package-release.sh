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

# Writes the bundle's current entitlements to $2 with the debugging-only
# get-task-allow key removed. Apple's notary service rejects any executable
# that requests it, and Xcode injects it into non-archive builds.
release_entitlements() {
  local bundle="$1" out="$2"
  codesign -d --entitlements :- "$bundle" 2>/dev/null > "$out"
  /usr/libexec/PlistBuddy -c 'Delete :com.apple.security.get-task-allow' "$out" 2>/dev/null || true
}

if [ -n "$SIGN_IDENTITY" ]; then
  log "Signing with: $SIGN_IDENTITY"
  ENT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nimbus-ent.XXXXXX")"
  # Sign inside-out so the embedded extension is sealed before the app that
  # contains it. Entitlements are re-applied from the build minus
  # get-task-allow; --options runtime enables the hardened runtime that
  # notarization requires.
  if [ -d "$APPEX" ]; then
    release_entitlements "$APPEX" "$ENT_DIR/appex.plist"
    codesign --force --timestamp --options runtime \
      --entitlements "$ENT_DIR/appex.plist" \
      --sign "$SIGN_IDENTITY" "$APPEX"
  fi
  release_entitlements "$APP" "$ENT_DIR/app.plist"
  codesign --force --timestamp --options runtime \
    --entitlements "$ENT_DIR/app.plist" \
    --sign "$SIGN_IDENTITY" "$APP"
  codesign --verify --deep --strict --verbose=2 "$APP"
  if codesign -d --entitlements :- "$APP" 2>/dev/null | grep -q get-task-allow; then
    echo "error: get-task-allow is still present after re-signing" >&2
    exit 1
  fi
  rm -rf "$ENT_DIR"
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
  SUBMISSION="$(xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json)"
  echo "$SUBMISSION"
  STATUS="$(printf '%s' "$SUBMISSION" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))')"
  if [ "$STATUS" != "Accepted" ]; then
    SUBMISSION_ID="$(printf '%s' "$SUBMISSION" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))')"
    echo "error: notarization status is '$STATUS'. Log:" >&2
    xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE" >&2 || true
    exit 1
  fi
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
