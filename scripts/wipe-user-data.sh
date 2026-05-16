#!/bin/bash
# Wipe every piece of Musique user data: settings, scrobble history, widget
# cache, Group Containers, and macOS permission grants (TCC).
#
# DESTRUCTIVE — back up first if you care about scrobble history or settings.
# Pair with scripts/clean-builds.sh to start from a totally clean slate.

set -uo pipefail

BUNDLE_ID="com.nopxx.musique"
GROUP_ID="group.com.nopxx.musique"
APP_NAME="Musique"

read -r -p "Wipe ALL ${APP_NAME} user data + permissions? [y/N] " yn
case "$yn" in
  y|Y|yes|YES) ;;
  *) echo "Aborted."; exit 1 ;;
esac

echo "==> Quitting ${APP_NAME}"
pkill -9 -x "$APP_NAME" 2>/dev/null || true
pkill -9 -x "${APP_NAME}Widget" 2>/dev/null || true
sleep 1

echo "==> Removing UserDefaults"
defaults delete "$BUNDLE_ID" 2>/dev/null || true
rm -f "${HOME}/Library/Preferences/${BUNDLE_ID}.plist"

echo "==> Removing Application Support (settings.json + history.db)"
rm -rf "${HOME}/Library/Application Support/${APP_NAME}"

echo "==> Removing Group Container (widget cache, nowPlaying, artwork)"
rm -rf "${HOME}/Library/Group Containers/${GROUP_ID}"

echo "==> Removing Caches"
rm -rf "${HOME}/Library/Caches/${BUNDLE_ID}"
rm -rf "${HOME}/Library/Caches/${GROUP_ID}"

echo "==> Removing Containers (best-effort; SIP may block)"
rm -rf "${HOME}/Library/Containers/${BUNDLE_ID}" 2>/dev/null || true

echo "==> Resetting TCC permissions (Apple Events, Notifications, etc.)"
tccutil reset All "$BUNDLE_ID" 2>/dev/null || true
tccutil reset All "${BUNDLE_ID}.widget" 2>/dev/null || true

echo "==> Restarting Notification Center"
killall usernoted 2>/dev/null || true
killall NotificationCenter 2>/dev/null || true

echo "==> Done. Next launch will hit default settings and re-prompt for permissions."
