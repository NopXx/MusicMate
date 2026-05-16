#!/bin/bash
# Wipe every cached Musique build artifact so the next install starts clean.
# Targets: running processes, /Applications copy, local build/, Xcode DerivedData,
# mounted DMGs, Trash leftovers, and LaunchServices / icon caches.
#
# Does NOT touch user data (settings, history, Group Containers). For that,
# run scripts/wipe-user-data.sh.

set -uo pipefail

BUNDLE_ID="com.nopxx.musique"
APP_NAME="Musique"

echo "==> Quitting running processes"
pkill -9 -x "$APP_NAME" 2>/dev/null || true
pkill -9 -x "${APP_NAME}Widget" 2>/dev/null || true
sleep 1

echo "==> Unmounting Musique DMG volumes"
for vol in /Volumes/${APP_NAME}*; do
  [ -d "$vol" ] || continue
  hdiutil detach "$vol" -force 2>/dev/null || true
done

echo "==> Removing installed + build copies"
rm -rf "/Applications/${APP_NAME}.app"
rm -rf "${HOME}/Library/Developer/Xcode/DerivedData/${APP_NAME}-"*
rm -rf "$(git rev-parse --show-toplevel 2>/dev/null || pwd)/build"

echo "==> Emptying Trash entries for ${APP_NAME}"
rm -rf "${HOME}/.Trash/${APP_NAME}"* 2>/dev/null || true

echo "==> Rebuilding LaunchServices database"
LSREG="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREG" -f -r -domain local -domain system -domain user >/dev/null 2>&1 || true

echo "==> Clearing icon + Notification Center caches"
rm -rf "${HOME}/Library/Caches/com.apple.iconservices.store" 2>/dev/null || true
find /private/var/folders -name "com.apple.dock.iconcache" -delete 2>/dev/null || true
find /private/var/folders -name "com.apple.iconservices" -type d -exec rm -rf {} + 2>/dev/null || true
killall usernoted 2>/dev/null || true
killall NotificationCenter 2>/dev/null || true
killall Dock 2>/dev/null || true
killall Finder 2>/dev/null || true

echo "==> Done. Stale paths still referenced by LaunchServices DB:"
"$LSREG" -dump 2>/dev/null | grep -E "path:.*${APP_NAME}\.app" || echo "  (none)"
