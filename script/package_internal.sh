#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Risper"
BUNDLE_ID="com.risper.Risper"
MIN_SYSTEM_VERSION="26.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
APP_ICON_SOURCE="$ROOT_DIR/Resources/AppIcon.icns"

WHISPER_BUILD_DIR="$ROOT_DIR/third_party/whisper.cpp/build"
WHISPER_SERVER_SOURCE="$WHISPER_BUILD_DIR/bin/whisper-server"
WHISPER_RESOURCE_DIR="$APP_RESOURCES/whisper.cpp"
WHISPER_BIN_DIR="$WHISPER_RESOURCE_DIR/bin"
WHISPER_LIB_DIR="$WHISPER_RESOURCE_DIR/lib"
WHISPER_SERVER_DEST="$WHISPER_BIN_DIR/whisper-server"

MODEL_SOURCE="$HOME/Library/Application Support/Risper/Models/ivrit-large-v3-turbo/ggml-model.bin"
MODEL_DEST_DIR="$APP_RESOURCES/Models/ivrit-large-v3-turbo"
MODEL_DEST="$MODEL_DEST_DIR/ggml-model.bin"

DMG_NAME="Risper-offline-arm64.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
DMG_RW_PATH="$DIST_DIR/Risper-offline-arm64-rw.dmg"
DMG_STAGE="$DIST_DIR/dmg-staging"
DMG_MOUNT_DIR="$DIST_DIR/dmg-mount"
DMG_VOLUME_NAME="Risper"
DMG_BACKGROUND_DIR_NAME=".background"
DMG_BACKGROUND_NAME="background.png"
DMG_BACKGROUND_PATH="$DMG_STAGE/$DMG_BACKGROUND_DIR_NAME/$DMG_BACKGROUND_NAME"

LOCAL_CODESIGN_IDENTITY="Risper Local Development Code Signing"
LOCAL_CODESIGN_DIR="$HOME/Library/Application Support/Risper/CodeSigning"
LOCAL_CODESIGN_KEYCHAIN="$LOCAL_CODESIGN_DIR/RisperLocalCodeSigning.keychain-db"
LOCAL_CODESIGN_PASSWORD_FILE="$LOCAL_CODESIGN_DIR/keychain-password"
LOCAL_CODESIGN_SEARCH_LIST_CHANGED=0
LOCAL_CODESIGN_UNLOCKED=0
LOCAL_CODESIGN_OLD_KEYCHAINS=()

CODESIGN_IDENTITY="-"

cd "$ROOT_DIR"

require_file() {
  local path="$1"
  local description="$2"

  if [[ ! -f "$path" ]]; then
    echo "error: missing $description: $path" >&2
    exit 1
  fi
}

require_executable() {
  local path="$1"
  local description="$2"

  if [[ ! -x "$path" ]]; then
    echo "error: missing executable $description: $path" >&2
    exit 1
  fi
}

prepare_codesigning() {
  if [[ -n "${RISPER_CODESIGN_IDENTITY:-}" ]]; then
    CODESIGN_IDENTITY="$RISPER_CODESIGN_IDENTITY"
    return
  fi

  if [[ -f "$LOCAL_CODESIGN_KEYCHAIN" || -f "$LOCAL_CODESIGN_PASSWORD_FILE" ]]; then
    if use_local_codesign_identity; then
      echo "package_internal: using stable local code-signing identity: $LOCAL_CODESIGN_IDENTITY"
      return
    fi

    echo "error: local code-signing identity exists but could not be unlocked or found" >&2
    echo "error: run script/setup_local_codesign.sh, then rerun script/package_internal.sh" >&2
    exit 1
  fi

  echo "warning: using ad-hoc signing; this build is not notarized" >&2
  echo "warning: run script/setup_local_codesign.sh for stable Accessibility trust" >&2
}

sign_file() {
  local path="$1"

  codesign --force --sign "$CODESIGN_IDENTITY" "$path"
}

sign_app() {
  codesign --force --deep --sign "$CODESIGN_IDENTITY" --identifier "$BUNDLE_ID" "$APP_BUNDLE"
}

restore_keychain_search_list() {
  if [[ "$#" -eq 0 ]]; then
    security list-keychains -d user -s >/dev/null
  else
    security list-keychains -d user -s "$@" >/dev/null
  fi
}

cleanup_codesigning() {
  if [[ "$LOCAL_CODESIGN_UNLOCKED" -eq 1 ]]; then
    security lock-keychain "$LOCAL_CODESIGN_KEYCHAIN" >/dev/null 2>&1 || true
    LOCAL_CODESIGN_UNLOCKED=0
  fi

  if [[ "$LOCAL_CODESIGN_SEARCH_LIST_CHANGED" -eq 1 ]]; then
    restore_keychain_search_list "${LOCAL_CODESIGN_OLD_KEYCHAINS[@]}" >/dev/null 2>&1 || true
    LOCAL_CODESIGN_SEARCH_LIST_CHANGED=0
  fi
}

use_local_codesign_identity() {
  local keychain
  local password

  if [[ ! -f "$LOCAL_CODESIGN_KEYCHAIN" || ! -r "$LOCAL_CODESIGN_PASSWORD_FILE" || ! -s "$LOCAL_CODESIGN_PASSWORD_FILE" ]]; then
    return 1
  fi

  password="$(<"$LOCAL_CODESIGN_PASSWORD_FILE")"
  LOCAL_CODESIGN_OLD_KEYCHAINS=()
  while IFS= read -r keychain; do
    keychain="${keychain#"${keychain%%[![:space:]]*}"}"
    keychain="${keychain%"${keychain##*[![:space:]]}"}"
    keychain="${keychain#\"}"
    keychain="${keychain%\"}"
    if [[ -n "$keychain" ]]; then
      LOCAL_CODESIGN_OLD_KEYCHAINS+=("$keychain")
    fi
  done < <(security list-keychains -d user)

  if ! security list-keychains -d user -s "$LOCAL_CODESIGN_KEYCHAIN" "${LOCAL_CODESIGN_OLD_KEYCHAINS[@]}" >/dev/null; then
    cleanup_codesigning
    return 1
  fi
  LOCAL_CODESIGN_SEARCH_LIST_CHANGED=1

  if ! security unlock-keychain -p "$password" "$LOCAL_CODESIGN_KEYCHAIN" >/dev/null; then
    cleanup_codesigning
    return 1
  fi
  LOCAL_CODESIGN_UNLOCKED=1

  if ! security find-identity -p codesigning -v "$LOCAL_CODESIGN_KEYCHAIN" | grep -Fq "$LOCAL_CODESIGN_IDENTITY"; then
    cleanup_codesigning
    return 1
  fi

  CODESIGN_IDENTITY="$LOCAL_CODESIGN_IDENTITY"
}

remove_rpath_if_present() {
  local target="$1"
  local rpath="$2"

  if otool -l "$target" | grep -Fq "path $rpath "; then
    install_name_tool -delete_rpath "$rpath" "$target"
  fi
}

add_rpath_if_missing() {
  local target="$1"
  local rpath="$2"

  if ! otool -l "$target" | grep -Fq "path $rpath "; then
    install_name_tool -add_rpath "$rpath" "$target"
  fi
}

rewrite_rpaths() {
  local target="$1"
  local package_rpath="$2"
  local rpath
  local build_rpaths=(
    "$WHISPER_BUILD_DIR/src"
    "$WHISPER_BUILD_DIR/ggml/src"
    "$WHISPER_BUILD_DIR/ggml/src/ggml-blas"
    "$WHISPER_BUILD_DIR/ggml/src/ggml-metal"
  )

  chmod u+w "$target"

  for rpath in "${build_rpaths[@]}"; do
    remove_rpath_if_present "$target" "$rpath"
  done

  add_rpath_if_missing "$target" "$package_rpath"
}

copy_dylib_family() {
  local directory="$1"
  local pattern="$2"
  local path

  for path in "$directory"/$pattern; do
    if [[ -e "$path" || -L "$path" ]]; then
      cp -P "$path" "$WHISPER_LIB_DIR/"
    fi
  done
}

copy_whisper_runtime() {
  mkdir -p "$WHISPER_BIN_DIR" "$WHISPER_LIB_DIR"
  cp -p "$WHISPER_SERVER_SOURCE" "$WHISPER_SERVER_DEST"

  copy_dylib_family "$WHISPER_BUILD_DIR/src" "libwhisper*.dylib"
  copy_dylib_family "$WHISPER_BUILD_DIR/ggml/src" "libggml*.dylib"
  copy_dylib_family "$WHISPER_BUILD_DIR/ggml/src/ggml-blas" "libggml-blas*.dylib"
  copy_dylib_family "$WHISPER_BUILD_DIR/ggml/src/ggml-metal" "libggml-metal*.dylib"

  rewrite_rpaths "$WHISPER_SERVER_DEST" "@executable_path/../lib"

  while IFS= read -r dylib; do
    rewrite_rpaths "$dylib" "@loader_path"
  done < <(find "$WHISPER_LIB_DIR" -type f -name "*.dylib" -print)
}

copy_model() {
  mkdir -p "$MODEL_DEST_DIR"
  cp -p "$MODEL_SOURCE" "$MODEL_DEST"
}

build_app_bundle() {
  local build_binary

  swift build -c release
  build_binary="$(swift build -c release --show-bin-path)/$APP_NAME"

  rm -rf "$APP_BUNDLE"
  mkdir -p "$APP_MACOS" "$APP_RESOURCES"
  cp "$build_binary" "$APP_BINARY"
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
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
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
}

sign_packaged_app() {
  while IFS= read -r dylib; do
    sign_file "$dylib"
  done < <(find "$WHISPER_LIB_DIR" -type f -name "*.dylib" -print)

  sign_file "$WHISPER_SERVER_DEST"
  sign_app
}

validate_packaged_app() {
  codesign --verify --deep --strict "$APP_BUNDLE"

  if otool -L "$WHISPER_SERVER_DEST" | awk 'NR > 1' | grep -Fq "$ROOT_DIR"; then
    echo "error: packaged whisper-server still links to the source checkout" >&2
    otool -L "$WHISPER_SERVER_DEST" >&2
    exit 1
  fi

  while IFS= read -r macho; do
    if otool -l "$macho" | awk 'NR > 1' | grep -Fq "$ROOT_DIR"; then
      echo "error: packaged runtime still has source-checkout rpaths: $macho" >&2
      otool -l "$macho" >&2
      exit 1
    fi
  done < <(find "$WHISPER_RESOURCE_DIR" -type f \( -name "whisper-server" -o -name "*.dylib" \) -print)
}

cleanup_dmg_artifacts() {
  if [[ -n "${DMG_MOUNT_DIR:-}" ]]; then
    hdiutil detach "$DMG_MOUNT_DIR" -quiet >/dev/null 2>&1 || true
  fi

  if [[ "${DMG_MOUNT_DIR:-}" == "$DIST_DIR/"* ]]; then
    rm -rf "$DMG_MOUNT_DIR"
  fi

  rm -f "$DMG_RW_PATH"
  rm -rf "$DMG_STAGE"
}

detach_existing_dmg_mounts() {
  local mount
  local mount_name

  while IFS= read -r mount; do
    mount_name="${mount##*/}"
    if [[ "$mount_name" == "$DMG_VOLUME_NAME" || "$mount_name" =~ ^$DMG_VOLUME_NAME\ [0-9]+$ ]]; then
      echo "package_internal: detaching existing DMG mount: $mount"
      hdiutil detach "$mount" -quiet >/dev/null 2>&1 || true
    fi
  done < <(find /Volumes -maxdepth 1 -type d -name "$DMG_VOLUME_NAME*" -print)
}

cleanup_on_exit() {
  local status=$?

  cleanup_dmg_artifacts
  cleanup_codesigning
  exit "$status"
}

generate_dmg_background() {
  local generator_path="$DIST_DIR/dmg-background.swift"

  mkdir -p "$(dirname "$DMG_BACKGROUND_PATH")"

  cat >"$generator_path" <<'SWIFT'
import AppKit
import Foundation

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let size = CGSize(width: 640, height: 400)
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size.width),
    pixelsHigh: Int(size.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .calibratedRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("error: unable to allocate DMG background bitmap\n", stderr)
    exit(1)
}
rep.size = size

func drawCentered(_ text: String, y: CGFloat, font: NSFont, color: NSColor) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: paragraph
    ]
    NSString(string: text).draw(
        in: CGRect(x: 42, y: y, width: size.width - 84, height: 36),
        withAttributes: attributes
    )
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let bounds = CGRect(origin: .zero, size: size)
NSGradient(
    starting: NSColor(calibratedRed: 0.94, green: 0.97, blue: 0.98, alpha: 1.0),
    ending: NSColor(calibratedRed: 0.99, green: 0.99, blue: 0.965, alpha: 1.0)
)?.draw(in: bounds, angle: 90)

let panel = NSBezierPath(roundedRect: CGRect(x: 28, y: 26, width: 584, height: 348), xRadius: 18, yRadius: 18)
NSColor(calibratedWhite: 1.0, alpha: 0.56).setFill()
panel.fill()
NSColor(calibratedRed: 0.74, green: 0.80, blue: 0.82, alpha: 0.55).setStroke()
panel.lineWidth = 1
panel.stroke()

drawCentered(
    "Risper",
    y: 310,
    font: NSFont.systemFont(ofSize: 34, weight: .semibold),
    color: NSColor(calibratedRed: 0.10, green: 0.17, blue: 0.20, alpha: 1.0)
)
drawCentered(
    "Drag Risper.app to Applications",
    y: 273,
    font: NSFont.systemFont(ofSize: 18, weight: .medium),
    color: NSColor(calibratedRed: 0.18, green: 0.27, blue: 0.30, alpha: 1.0)
)
drawCentered(
    "Offline build - local ASR; Microphone + Accessibility required",
    y: 58,
    font: NSFont.systemFont(ofSize: 13, weight: .regular),
    color: NSColor(calibratedRed: 0.38, green: 0.46, blue: 0.48, alpha: 1.0)
)

let arrow = NSBezierPath()
arrow.move(to: CGPoint(x: 256, y: 196))
arrow.line(to: CGPoint(x: 384, y: 196))
arrow.lineWidth = 5
arrow.lineCapStyle = .round
NSColor(calibratedRed: 0.12, green: 0.47, blue: 0.50, alpha: 0.88).setStroke()
arrow.stroke()

let arrowHead = NSBezierPath()
arrowHead.move(to: CGPoint(x: 384, y: 196))
arrowHead.line(to: CGPoint(x: 364, y: 210))
arrowHead.move(to: CGPoint(x: 384, y: 196))
arrowHead.line(to: CGPoint(x: 364, y: 182))
arrowHead.lineWidth = 5
arrowHead.lineCapStyle = .round
arrowHead.lineJoinStyle = .round
arrowHead.stroke()

NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else {
    fputs("error: unable to render DMG background\n", stderr)
    exit(1)
}

try data.write(to: outputURL, options: .atomic)
SWIFT

  swift "$generator_path" "$DMG_BACKGROUND_PATH"
  rm -f "$generator_path"
}

configure_dmg_finder_window() {
  local mounted_background_path="$DMG_MOUNT_DIR/$DMG_BACKGROUND_DIR_NAME/$DMG_BACKGROUND_NAME"

  if ! osascript <<OSA
set backgroundFile to POSIX file "$mounted_background_path" as alias

tell application "Finder"
  tell disk "$DMG_VOLUME_NAME"
    open
    delay 1
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {120, 120, 760, 520}

    set viewOptions to icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 96
    set background picture of viewOptions to backgroundFile

    set position of item "$APP_NAME.app" to {170, 205}
    set position of item "Applications" to {470, 205}
    set position of item "README.txt" to {320, 330}

    update without registering applications
    delay 2
    close container window
  end tell
end tell
OSA
  then
    echo "error: unable to configure the DMG Finder window" >&2
    echo "error: allow Finder automation for the packaging shell in System Settings > Privacy & Security > Automation, then rerun script/package_internal.sh" >&2
    exit 1
  fi
}

attach_dmg_for_layout() {
  local attach_output

  attach_output="$(hdiutil attach "$DMG_RW_PATH" -readwrite -noverify -noautoopen)"
  DMG_MOUNT_DIR="$(printf '%s\n' "$attach_output" | awk -F '\t' 'NF >= 3 && $NF != "" { mount = $NF } END { print mount }')"

  if [[ -z "$DMG_MOUNT_DIR" || ! -d "$DMG_MOUNT_DIR" ]]; then
    echo "error: unable to determine mounted DMG path" >&2
    printf '%s\n' "$attach_output" >&2
    exit 1
  fi
}

create_dmg() {
  detach_existing_dmg_mounts
  rm -rf "$DMG_STAGE" "$DMG_PATH" "$DMG_RW_PATH" "$DMG_MOUNT_DIR"
  mkdir -p "$DMG_STAGE"

  ditto "$APP_BUNDLE" "$DMG_STAGE/$APP_NAME.app"
  ln -s /Applications "$DMG_STAGE/Applications"
  generate_dmg_background

  cat >"$DMG_STAGE/README.txt" <<README
Risper Offline Build

This DMG contains a self-contained Risper.app with the local whisper.cpp runtime
and the bundled Ivrit.ai Hebrew model. It does not need the source repo or an
internet connection after install.

Install:
1. Drag Risper.app to Applications.
2. The first launch is blocked because the app is not notarized. Open
   System Settings > Privacy & Security, find the message that Risper was
   blocked, and click Open Anyway. Then launch Risper again.
3. Grant Microphone permission when prompted.
4. Grant Accessibility permission from System Settings > Privacy & Security > Accessibility.
   Risper uses Accessibility for long-press fn detection and cursor insertion.
   If Risper already appears enabled but still reports Accessibility as required,
   remove Risper from the list, add /Applications/Risper.app again, and relaunch.

This build is locally signed and is not notarized.
README

  hdiutil create -volname "$DMG_VOLUME_NAME" -srcfolder "$DMG_STAGE" -ov -format UDRW -fs HFS+ "$DMG_RW_PATH"

  attach_dmg_for_layout
  SetFile -a V "$DMG_MOUNT_DIR/$DMG_BACKGROUND_DIR_NAME"
  configure_dmg_finder_window
  rm -rf "$DMG_MOUNT_DIR/.fseventsd"
  sync
  hdiutil detach "$DMG_MOUNT_DIR" -quiet

  hdiutil convert "$DMG_RW_PATH" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH"
  hdiutil verify "$DMG_PATH"
  cleanup_dmg_artifacts
}

require_executable "$WHISPER_SERVER_SOURCE" "whisper-server"
require_file "$MODEL_SOURCE" "Ivrit.ai model"

trap cleanup_on_exit EXIT
trap 'trap - EXIT HUP INT TERM; cleanup_dmg_artifacts; cleanup_codesigning; exit 129' HUP
trap 'trap - EXIT HUP INT TERM; cleanup_dmg_artifacts; cleanup_codesigning; exit 130' INT
trap 'trap - EXIT HUP INT TERM; cleanup_dmg_artifacts; cleanup_codesigning; exit 143' TERM

mkdir -p "$DIST_DIR"
prepare_codesigning
build_app_bundle
copy_whisper_runtime
copy_model
sign_packaged_app
cleanup_codesigning
validate_packaged_app
create_dmg

echo "Created $DMG_PATH"
