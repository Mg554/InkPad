#!/usr/bin/env bash
# Build the feature branch from this worktree and install it on the owner's
# real iPad with the free Personal Team. Run from anywhere.
#
#   ./scripts/install-inkpad-to-ipad.sh
#
# Optional overrides:
#   DEVICE_UDID=00008112-001E213A1E93A01E DEVICE_ID=FB9997CE-... \
#   ./scripts/install-inkpad-to-ipad.sh
#
# The free signature expires after 7 days: run this again to re-sign.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE="$ROOT/InkPad.swiftpm"
DERIVED="$ROOT/.build/ipad-derived"

# Values from CLAUDE.md; override with environment variables if the iPad
# or its developer-mode id changes.
DEVICE_UDID="${DEVICE_UDID:-00008112-001E213A1E93A01E}"
DEVICE_ID="${DEVICE_ID:-FB9997CE-4771-5D00-8F3D-1C300CD8ABBE}"

echo "==> Building from $PACKAGE"
cd "$PACKAGE"
xcodebuild -scheme InkPad \
  -destination "id=$DEVICE_UDID" \
  -allowProvisioningUpdates \
  -derivedDataPath "$DERIVED" \
  build

APP="$(find "$DERIVED/Build/Products" -type d -name 'InkPad.app' -print -quit)"
if [[ -z "$APP" ]]; then
  echo "Could not find InkPad.app under $DERIVED" >&2
  exit 1
fi
echo "==> App: $APP"

echo "==> Installing on $DEVICE_ID"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP"

echo "==> Done. Open InkPad on the iPad (the icon may be in a different place after reinstalling)."
echo "    This free signature lasts 7 days; run the script again to re-sign."
