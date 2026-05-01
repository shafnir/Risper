#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Risper"
BUNDLE_ID="com.risper.Risper"
MIN_SYSTEM_VERSION="26.0"
LOCAL_CODESIGN_IDENTITY="Risper Local Development Code Signing"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
APP_ICON_SOURCE="$ROOT_DIR/Resources/AppIcon.icns"
LOCAL_CODESIGN_DIR="$HOME/Library/Application Support/Risper/CodeSigning"
LOCAL_CODESIGN_KEYCHAIN="$LOCAL_CODESIGN_DIR/RisperLocalCodeSigning.keychain-db"
LOCAL_CODESIGN_PASSWORD_FILE="$LOCAL_CODESIGN_DIR/keychain-password"

cd "$ROOT_DIR"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

swift build
BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
cp "$APP_ICON_SOURCE" "$APP_RESOURCES/AppIcon.icns"
chmod +x "$APP_BINARY"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSInputMonitoringUsageDescription</key>
  <string>Risper observes the fn key and fallback shortcut to start and stop local dictation.</string>
  <key>NSAppTransportSecurity</key>
  <dict>
    <key>NSAllowsLocalNetworking</key>
    <true/>
  </dict>
  <key>NSMicrophoneUsageDescription</key>
  <string>Risper records speech locally for Hebrew dictation.</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

restore_keychain_search_list() {
  if [[ "$#" -eq 0 ]]; then
    security list-keychains -d user -s >/dev/null
  else
    security list-keychains -d user -s "$@" >/dev/null
  fi
}

sign_with_local_keychain() {
  local password
  local status
  local cleanup_status
  local search_list_changed=0
  local unlocked=0
  local old_keychains=()

  cleanup_local_codesign_keychain() {
    local command_status
    local result=0

    if [[ "$unlocked" -eq 1 ]]; then
      security lock-keychain "$LOCAL_CODESIGN_KEYCHAIN" >/dev/null
      command_status=$?
      if [[ "$command_status" -ne 0 && "$result" -eq 0 ]]; then
        result="$command_status"
      fi
      unlocked=0
    fi

    if [[ "$search_list_changed" -eq 1 ]]; then
      restore_keychain_search_list "${old_keychains[@]}"
      command_status=$?
      if [[ "$command_status" -ne 0 && "$result" -eq 0 ]]; then
        result="$command_status"
      fi
      search_list_changed=0
    fi

    return "$result"
  }

  password="$(<"$LOCAL_CODESIGN_PASSWORD_FILE")"
  while IFS= read -r keychain; do
    keychain="${keychain#"${keychain%%[![:space:]]*}"}"
    keychain="${keychain%"${keychain##*[![:space:]]}"}"
    keychain="${keychain#\"}"
    keychain="${keychain%\"}"
    if [[ -n "$keychain" ]]; then
      old_keychains+=("$keychain")
    fi
  done < <(security list-keychains -d user)

  trap 'cleanup_local_codesign_keychain; trap - HUP INT TERM; exit 129' HUP
  trap 'cleanup_local_codesign_keychain; trap - HUP INT TERM; exit 130' INT
  trap 'cleanup_local_codesign_keychain; trap - HUP INT TERM; exit 143' TERM

  set +e
  search_list_changed=1
  security list-keychains -d user -s "$LOCAL_CODESIGN_KEYCHAIN" "${old_keychains[@]}"
  status=$?

  if [[ "$status" -eq 0 ]]; then
    security unlock-keychain -p "$password" "$LOCAL_CODESIGN_KEYCHAIN"
    status=$?
    if [[ "$status" -eq 0 ]]; then
      unlocked=1
      codesign --force --deep --sign "$LOCAL_CODESIGN_IDENTITY" --identifier "$BUNDLE_ID" "$APP_BUNDLE"
      status=$?
    fi
  fi
  cleanup_local_codesign_keychain
  cleanup_status=$?
  trap - HUP INT TERM
  unset -f cleanup_local_codesign_keychain
  set -e

  if [[ "$cleanup_status" -ne 0 ]]; then
    return "$cleanup_status"
  fi
  return "$status"
}

sign_app() {
  if [[ -n "${RISPER_CODESIGN_IDENTITY:-}" ]]; then
    codesign --force --deep --sign "$RISPER_CODESIGN_IDENTITY" --identifier "$BUNDLE_ID" "$APP_BUNDLE"
    return
  fi

  if [[ -f "$LOCAL_CODESIGN_KEYCHAIN" && -f "$LOCAL_CODESIGN_PASSWORD_FILE" ]]; then
    sign_with_local_keychain
    return
  fi

  echo "warning: using ad-hoc signing; Accessibility permission may reset after rebuilds" >&2
  echo "warning: run script/setup_local_codesign.sh for stable local Accessibility trust" >&2
  codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$APP_BUNDLE"
}

sign_app

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
