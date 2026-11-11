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
#   5. If NIMBUS_SPARKLE_KEY is set, sign the finished DMG for Sparkle and
#      write dist/appcast.xml (scripts/make-appcast.sh), then check it
#      against the SUPublicEDKey of the app in the DMG.
#
# Environment:
#   NIMBUS_SIGN_IDENTITY   e.g. "Developer ID Application: Your Name (TEAMID)"
#   NIMBUS_NOTARY_PROFILE  a keychain profile created with
#                          `xcrun notarytool store-credentials <name>`
#   NIMBUS_SPARKLE_KEY     the Sparkle EdDSA private key (`generate_keys -x`)
#   NIMBUS_SKIP_BUILD=1    package the existing Release build without rebuilding
#   NIMBUS_DIST_DIR        output directory (default: <repo>/dist)
#
# Without the two signing variables the script produces an unsigned DMG that
# is fine for local testing but will be blocked by Gatekeeper on other Macs.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILT_APP="$ROOT_DIR/Nimbus/build/Build/Products/Release/Nimbus.app"
DIST_DIR="${NIMBUS_DIST_DIR:-$ROOT_DIR/dist}"
SIGN_IDENTITY="${NIMBUS_SIGN_IDENTITY:-}"
NOTARY_PROFILE="${NIMBUS_NOTARY_PROFILE:-}"

log() { printf '==> %s\n' "$*"; }

if [ "${NIMBUS_SKIP_BUILD:-0}" != "1" ]; then
  bash "$ROOT_DIR/scripts/build-release.sh"
fi

if [ ! -d "$BUILT_APP" ]; then
  echo "error: $BUILT_APP not found. Run scripts/build-release.sh first." >&2
  exit 1
fi

# Work on a copy. The build products stay exactly as Xcode left them, so an
# incremental rebuild never sees a half re-signed bundle.
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/nimbus-dmg.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
ditto "$BUILT_APP" "$STAGE/Nimbus.app"
APP="$STAGE/Nimbus.app"
APPEX="$APP/Contents/PlugIns/FileProviderExtension.appex"
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"

# Every release runs on Apple silicon and Intel: refuse a build missing either.
for binary in "$APP/Contents/MacOS/Nimbus" "$APPEX/Contents/MacOS/FileProviderExtension"; do
  archs="$(lipo -archs "$binary")"
  for arch in arm64 x86_64; do
    case " $archs " in
      *" $arch "*) ;;
      *) echo "error: $(basename "$binary") is missing $arch (has: $archs)" >&2; exit 1 ;;
    esac
  done
done

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
DMG="$DIST_DIR/Nimbus-$VERSION.dmg"
VOLNAME="Nimbus $VERSION"

mkdir -p "$DIST_DIR"
rm -f "$DMG" "$DMG.sha256"

# Writes the bundle's current entitlements to $2 minus the keys a Developer
# ID build must not carry:
#   - com.apple.security.get-task-allow: debugging only; the notary service
#     rejects any executable that requests it.
#   - com.apple.application-identifier and com.apple.developer.team-identifier:
#     restricted entitlements that only a provisioning profile can authorize.
#     Xcode's automatic (Apple Development) signing adds them together with a
#     development profile. Re-signed with a Developer ID certificate, that
#     profile no longer matches and launchd refuses to spawn the app
#     ("Launchd job spawn failed", no crash log). 0.9.0 shipped that way.
# The app group entitlement stays: on macOS it needs no profile.
release_entitlements() {
  local bundle="$1" out="$2" source="$3"
  codesign -d --entitlements :- "$bundle" 2>/dev/null > "$out" || true
  # An unsigned build (NIMBUS_UNSIGNED_BUILD=1, CI) carries none: use the
  # checked-in file, which holds exactly what a release needs.
  if ! /usr/libexec/PlistBuddy -c "Print" "$out" >/dev/null 2>&1; then
    cp "$source" "$out"
  fi
  local key
  for key in com.apple.security.get-task-allow com.apple.application-identifier com.apple.developer.team-identifier; do
    /usr/libexec/PlistBuddy -c "Delete :$key" "$out" 2>/dev/null || true
  done
}

# Removes the development provisioning profile Xcode embedded, for the same
# reason: it names Apple Development certificates and a device list, neither
# of which applies to a Developer ID build.
drop_dev_profile() {
  rm -f "$1/Contents/embedded.provisionprofile"
}

if [ -n "$SIGN_IDENTITY" ]; then
  log "Signing with: $SIGN_IDENTITY"
  ENT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nimbus-ent.XXXXXX")"
  # Sign inside-out so the embedded extension is sealed before the app that
  # contains it. Entitlements are re-applied from the build minus
  # get-task-allow; --options runtime enables the hardened runtime that
  # notarization requires.
  drop_dev_profile "$APP"
  # Sparkle's helpers first, innermost out, as its documentation orders them.
  # Signing the app does not sign code nested in a framework, and CI builds
  # unsigned, so without this they keep the Sparkle project's signature and
  # the notary service rejects the app. Downloader.xpc keeps its entitlements.
  if [ -d "$SPARKLE" ]; then
    SPARKLE_CODE="$SPARKLE/Versions/Current"
    codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" "$SPARKLE_CODE/XPCServices/Installer.xpc"
    codesign --force --timestamp --options runtime --preserve-metadata=entitlements \
      --sign "$SIGN_IDENTITY" "$SPARKLE_CODE/XPCServices/Downloader.xpc"
    codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" "$SPARKLE_CODE/Autoupdate"
    codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" "$SPARKLE_CODE/Updater.app"
    codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" "$SPARKLE"
  fi
  if [ -d "$APPEX" ]; then
    drop_dev_profile "$APPEX"
    release_entitlements "$APPEX" "$ENT_DIR/appex.plist" "$ROOT_DIR/Nimbus/FileProviderExtension/FileProviderExtension.entitlements"
    codesign --force --timestamp --options runtime \
      --entitlements "$ENT_DIR/appex.plist" \
      --sign "$SIGN_IDENTITY" "$APPEX"
  fi
  release_entitlements "$APP" "$ENT_DIR/app.plist" "$ROOT_DIR/Nimbus/Nimbus/Nimbus.entitlements"
  codesign --force --timestamp --options runtime \
    --entitlements "$ENT_DIR/app.plist" \
    --sign "$SIGN_IDENTITY" "$APP"
  codesign --verify --deep --strict --verbose=2 "$APP"
  for key in get-task-allow application-identifier team-identifier; do
    if codesign -d --entitlements :- "$APP" 2>/dev/null | grep -q "$key"; then
      echo "error: $key is still present after re-signing" >&2
      exit 1
    fi
  done
  if [ -e "$APP/Contents/embedded.provisionprofile" ]; then
    echo "error: embedded.provisionprofile is still present" >&2
    exit 1
  fi
  # The real test: a Developer ID build must spawn. Launch it headless for a
  # moment and make sure launchd accepted it, then quit it again.
  log "Launch check"
  if ! open -g -a "$APP" --args -NSQuitAlwaysKeepsWindows NO; then
    echo "error: the re-signed app failed to launch" >&2
    exit 1
  fi
  sleep 4
  if ! pgrep -x Nimbus >/dev/null; then
    echo "error: the re-signed app did not stay running" >&2
    exit 1
  fi
  pkill -x Nimbus || true
  sleep 1
  rm -rf "$ENT_DIR"
else
  log "NIMBUS_SIGN_IDENTITY not set; leaving the app with its build signature"
fi

log "Creating $DMG"
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

# The appcast signs the DMG's bytes, so it comes after stapling, which
# rewrites the DMG.
rm -f "$DIST_DIR/appcast.xml"
if [ -n "${NIMBUS_SPARKLE_KEY:-}" ]; then
  log "Writing the Sparkle appcast"
  MIN_OS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP/Contents/Info.plist")"
  PUBLIC_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$APP/Contents/Info.plist")"
  bash "$ROOT_DIR/scripts/make-appcast.sh" "$DMG" "$VERSION" "$MIN_OS" "$DIST_DIR/appcast.xml"
  if ! xcrun swift "$ROOT_DIR/scripts/verify-appcast.swift" "$DIST_DIR/appcast.xml" "$DMG" "$PUBLIC_KEY"; then
    # Never leave an appcast that installed copies would reject.
    rm -f "$DIST_DIR/appcast.xml"
    exit 1
  fi
else
  log "NIMBUS_SPARKLE_KEY not set; no appcast, so this build is not offered as an update"
fi

log "Done: $DMG (Nimbus $VERSION, build $BUILD)"
cat "$DMG.sha256"
