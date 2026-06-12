#!/usr/bin/env bash
set -euo pipefail

# Risper one-line installer.
#
# Downloads the latest offline Risper DMG with curl, copies Risper.app into
# /Applications, and launches it. Because curl (unlike a web browser) does not
# attach the com.apple.quarantine flag, macOS Gatekeeper does not show the
# "Apple could not verify Risper is free of malware" dialog. See
# docs/debugging-macos-permissions.md for the quarantine/notarization details.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/shafnir/Risper/main/script/install.sh | bash

APP_NAME="Risper"
DMG_NAME="Risper-offline-arm64.dmg"
REPO="shafnir/Risper"
DMG_URL="https://github.com/$REPO/releases/latest/download/$DMG_NAME"
CHECKSUM_URL="$DMG_URL.sha256"
INSTALL_DIR="/Applications"
APP_DEST="$INSTALL_DIR/$APP_NAME.app"

log()  { printf 'install: %s\n' "$*"; }
warn() { printf 'install: warning: %s\n' "$*" >&2; }
fail() { printf 'install: error: %s\n' "$*" >&2; exit 1; }

# --- Preflight -------------------------------------------------------------

[[ "$(uname -s)" == "Darwin" ]] || fail "Risper requires macOS."
[[ "$(uname -m)" == "arm64" ]] || fail "Risper requires an Apple Silicon (arm64) Mac."

OS_MAJOR="$(sw_vers -productVersion 2>/dev/null | cut -d. -f1)"
if [[ "$OS_MAJOR" =~ ^[0-9]+$ ]] && (( OS_MAJOR < 26 )); then
  warn "Risper needs macOS 26 or newer (you have $(sw_vers -productVersion)); it may not launch."
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/risper-install.XXXXXX")"
MOUNT_POINT=""
cleanup() {
  [[ -n "$MOUNT_POINT" && -d "$MOUNT_POINT" ]] && hdiutil detach "$MOUNT_POINT" -force -quiet 2>/dev/null || true
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

DMG_PATH="$WORK_DIR/$DMG_NAME"

# --- Download (no quarantine flag, this is the whole point) -----------------

log "Downloading the latest $APP_NAME release..."
curl -fSL --progress-bar -o "$DMG_PATH" "$DMG_URL" \
  || fail "Download failed. Check your connection or see https://github.com/$REPO/releases/latest"

# --- Optional integrity check ----------------------------------------------

if EXPECTED="$(curl -fsSL "$CHECKSUM_URL" 2>/dev/null)"; then
  EXPECTED="$(printf '%s' "$EXPECTED" | awk 'NR==1{print $1; exit}')"
  ACTUAL="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
  if [[ "$EXPECTED" != "$ACTUAL" ]]; then
    fail "Checksum mismatch — refusing to install. Expected $EXPECTED, got $ACTUAL."
  fi
  log "Checksum verified."
else
  warn "No published checksum found; relying on the HTTPS download. Continuing."
fi

# --- Mount, copy, detach ---------------------------------------------------

log "Mounting the disk image..."
# hdiutil prints "<dev node><tab><type><tab><mount point>"; grab the mount path
# only (everything from /Volumes/ to end of line), trimming trailing whitespace.
MOUNT_POINT="$(hdiutil attach "$DMG_PATH" -nobrowse -readonly \
  | sed -nE 's#.*(/Volumes/.*)$#\1#p' | tail -1 | sed -E 's/[[:space:]]+$//')"
[[ -n "$MOUNT_POINT" && -d "$MOUNT_POINT" ]] || fail "Could not mount the disk image."

SRC_APP="$MOUNT_POINT/$APP_NAME.app"
[[ -d "$SRC_APP" ]] || SRC_APP="$(find "$MOUNT_POINT" -maxdepth 1 -name '*.app' -print -quit)"
[[ -n "$SRC_APP" && -d "$SRC_APP" ]] || fail "Could not find $APP_NAME.app inside the disk image."

# Stop a running copy so the bundle can be replaced cleanly.
if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
  log "Quitting the running copy of $APP_NAME..."
  osascript -e "quit app \"$APP_NAME\"" 2>/dev/null || true
  sleep 1
  pkill -x "$APP_NAME" 2>/dev/null || true
fi

# Choose whether we need sudo to write to /Applications.
SUDO=""
if [[ ! -w "$INSTALL_DIR" ]]; then
  SUDO="sudo"
  log "Installing to $INSTALL_DIR requires administrator access."
fi

log "Installing $APP_NAME to $INSTALL_DIR..."
$SUDO rm -rf "$APP_DEST"
$SUDO cp -R "$SRC_APP" "$APP_DEST"

if hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null; then
  MOUNT_POINT=""  # detached cleanly; the EXIT trap no longer needs to retry
fi

# Defensive: clear any quarantine flag in case the bundle was ever tagged.
$SUDO xattr -dr com.apple.quarantine "$APP_DEST" 2>/dev/null || true

# --- Launch + next steps ---------------------------------------------------

log "Launching $APP_NAME..."
open "$APP_DEST" || warn "Could not auto-launch; open $APP_DEST manually."

cat <<EOF

✅ $APP_NAME is installed at $APP_DEST and should be opening now.

Next, grant the two permissions Risper needs:
  1. Microphone — approve the prompt on first use.
  2. Accessibility — System Settings → Privacy & Security → Accessibility,
     enable Risper, then quit and relaunch Risper.

Then hold the fn key, speak Hebrew, release, and the text is inserted at your
cursor. Full guide: https://github.com/$REPO#using-risper
EOF
