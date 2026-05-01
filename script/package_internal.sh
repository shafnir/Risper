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

WHISPER_BUILD_DIR="$ROOT_DIR/third_party/whisper.cpp/build"
WHISPER_SERVER_SOURCE="$WHISPER_BUILD_DIR/bin/whisper-server"
WHISPER_RESOURCE_DIR="$APP_RESOURCES/whisper.cpp"
WHISPER_BIN_DIR="$WHISPER_RESOURCE_DIR/bin"
WHISPER_LIB_DIR="$WHISPER_RESOURCE_DIR/lib"
WHISPER_SERVER_DEST="$WHISPER_BIN_DIR/whisper-server"

MODEL_SOURCE="$HOME/Library/Application Support/Risper/Models/ivrit-large-v3-turbo/ggml-model.bin"
MODEL_DEST_DIR="$APP_RESOURCES/Models/ivrit-large-v3-turbo"
MODEL_DEST="$MODEL_DEST_DIR/ggml-model.bin"

DMG_NAME="Risper-internal-offline-arm64.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
DMG_STAGE="$DIST_DIR/dmg-staging"
DMG_VOLUME_NAME="Risper Internal"

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

  echo "warning: using ad-hoc signing; this build is not notarized" >&2
}

sign_file() {
  local path="$1"

  codesign --force --sign "$CODESIGN_IDENTITY" "$path"
}

sign_app() {
  codesign --force --deep --sign "$CODESIGN_IDENTITY" --identifier "$BUNDLE_ID" "$APP_BUNDLE"
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
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0-internal</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
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

create_dmg() {
  rm -rf "$DMG_STAGE" "$DMG_PATH"
  mkdir -p "$DMG_STAGE"

  ditto "$APP_BUNDLE" "$DMG_STAGE/$APP_NAME.app"
  ln -s /Applications "$DMG_STAGE/Applications"

  cat >"$DMG_STAGE/README - Internal Build.txt" <<README
Risper Internal Offline Build

This DMG contains a self-contained Risper.app with the local whisper.cpp runtime
and the bundled Ivrit.ai Hebrew model. It does not need the source repo or an
internet connection after install.

Install:
1. Drag Risper.app to Applications.
2. If macOS blocks first launch, right-click Risper.app and choose Open.
3. Grant Microphone and Accessibility permissions when prompted or from System Settings.

This build is locally/ad-hoc signed for internal testing and is not notarized.
README

  hdiutil create -volname "$DMG_VOLUME_NAME" -srcfolder "$DMG_STAGE" -ov -format UDZO "$DMG_PATH"
  hdiutil verify "$DMG_PATH"
}

require_executable "$WHISPER_SERVER_SOURCE" "whisper-server"
require_file "$MODEL_SOURCE" "Ivrit.ai model"

mkdir -p "$DIST_DIR"
prepare_codesigning
build_app_bundle
copy_whisper_runtime
copy_model
sign_packaged_app
validate_packaged_app
create_dmg

echo "Created $DMG_PATH"
