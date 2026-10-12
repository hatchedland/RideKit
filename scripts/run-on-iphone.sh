#!/usr/bin/env bash
# Builds the free "Personal" version (no iCloud) and installs + launches it on a USB-connected iPhone.
#
# One-time setup:
#   1. Xcode › Settings › Accounts › "+" › Apple ID (a free account is fine)
#   2. Connect the iPhone by cable, unlock it, tap "Trust This Computer"
#   3. On the iPhone: Settings › Privacy & Security › Developer Mode › On (it restarts)
#
# Usage:  ./scripts/run-on-iphone.sh [TEAM_ID]
# The Team ID is detected from Xcode's signed-in account when not given.
# Free-account installs expire after 7 days; just run this again (your data is kept).
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

TEAM_ID="${1:-${TEAM_ID:-}}"
if [ -z "$TEAM_ID" ]; then
  # Signing certificates name the team in parentheses: "Apple Development: Name (ABCDE12345)".
  TEAM_ID=$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*Apple Development: .*(\([A-Z0-9]\{10\}\)).*/\1/p' | head -1 || true)
fi
if [ -z "$TEAM_ID" ]; then
  # Before the first build there's no certificate yet; read the team from Xcode's account list.
  TEAM_ID=$(defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier 2>/dev/null \
    | sed -n 's/.*teamID = \([A-Z0-9]\{10\}\);.*/\1/p' | head -1 || true)
fi
if [ -z "$TEAM_ID" ]; then
  echo "No Apple ID found in Xcode. Add one in Xcode › Settings › Accounts, then run this again." >&2
  echo "(Or pass your Team ID: ./scripts/run-on-iphone.sh ABCDE12345)" >&2
  exit 1
fi

DEVICE_ID=$(xcrun devicectl list devices 2>/dev/null | awk '/iPhone/ && /(available|connected)/ {for (i=1;i<=NF;i++) if ($i ~ /^[0-9A-F]{8}-/) {print $i; exit}}' || true)
if [ -z "$DEVICE_ID" ]; then
  echo "No iPhone found. Connect it by cable, unlock it, trust this Mac, and turn on Developer Mode." >&2
  xcrun devicectl list devices >&2 || true
  exit 1
fi

echo "Team $TEAM_ID → iPhone $DEVICE_ID"
xcodegen generate --quiet
xcodebuild -project RideTracker.xcodeproj -scheme "RideTracker (Personal)" \
  -destination "id=$DEVICE_ID" -derivedDataPath build/DerivedData \
  -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM_ID" build | grep -E "error:|warning:|BUILD (SUCCEEDED|FAILED)"

APP=build/DerivedData/Build/Products/Personal-iphoneos/RideTracker.app
xcrun devicectl device install app --device "$DEVICE_ID" "$APP"
xcrun devicectl device process launch --device "$DEVICE_ID" com.hatchedland.ridetracker || {
  echo
  echo "Installed, but iOS blocked the launch. On the iPhone go to Settings › General ›"
  echo "VPN & Device Management, tap your Apple ID under Developer App, then Trust. Then open Ride Tracker."
}
