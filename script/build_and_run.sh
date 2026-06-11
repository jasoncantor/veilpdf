#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="VeilPDF"
BUNDLE_ID="dev.jasoncantor.VeilPDF"
MIN_SYSTEM_VERSION="14.0"
APP_VERSION="${APP_VERSION:-0.2.0}"
CODE_SIGN_IDENTITY="${VEILPDF_CODESIGN_IDENTITY:--}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
APP_REDACTOR_BINARY="$APP_MACOS/hide-pii-redactor"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ICONSET_DIR="$DIST_DIR/AppIcon.iconset"
APP_ICON="$APP_RESOURCES/$APP_NAME.icns"
RUST_MANIFEST="$ROOT_DIR/RustRedactor/Cargo.toml"
RUST_BINARY="$ROOT_DIR/RustRedactor/target/debug/hide-pii-redactor"
HELPER_SCRIPT="$ROOT_DIR/scripts/gliner_pii_redactor.py"
if [[ -x "$ROOT_DIR/.venv/bin/python" ]]; then
  DEFAULT_PYTHON="$ROOT_DIR/.venv/bin/python"
else
  DEFAULT_PYTHON="$(command -v python3 || command -v python3.12 || command -v python3.11 || true)"
fi
DEFAULT_PYTHON="${DEFAULT_PYTHON:-python3}"

export VEILPDF_PROJECT_ROOT="$ROOT_DIR"
export VEILPDF_REDACTOR="$RUST_BINARY"
export VEILPDF_HELPER="$HELPER_SCRIPT"
export VEILPDF_PYTHON="${VEILPDF_PYTHON:-$DEFAULT_PYTHON}"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
pkill -f "$APP_BINARY" >/dev/null 2>&1 || true

build_all() {
  cargo build --manifest-path "$RUST_MANIFEST"
  swift build --package-path "$ROOT_DIR"
  local swift_bin_dir
  swift_bin_dir="$(swift build --package-path "$ROOT_DIR" --show-bin-path)"

  rm -rf "$APP_BUNDLE"
  mkdir -p "$APP_MACOS" "$APP_RESOURCES"
  cp "$swift_bin_dir/$APP_NAME" "$APP_BINARY"
  cp "$RUST_BINARY" "$APP_REDACTOR_BINARY"
  cp "$HELPER_SCRIPT" "$APP_RESOURCES/gliner_pii_redactor.py"
  chmod +x "$APP_BINARY"
  chmod +x "$APP_REDACTOR_BINARY"
  chmod 0644 "$APP_RESOURCES/gliner_pii_redactor.py"
  swift "$ROOT_DIR/script/generate_app_icon.swift" "$ICONSET_DIR"
  iconutil -c icns "$ICONSET_DIR" -o "$APP_ICON"

  cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_VERSION</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.productivity</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

  sign_target "$APP_REDACTOR_BINARY"
  sign_target "$APP_BINARY"
  sign_target "$APP_BUNDLE"
}

sign_target() {
  local target="$1"
  local deep_arg=""
  if [[ "$target" == *.app ]]; then
    deep_arg="--deep"
  fi
  if [[ "$CODE_SIGN_IDENTITY" == "-" || -z "$CODE_SIGN_IDENTITY" ]]; then
    codesign --force ${deep_arg:+"$deep_arg"} --sign - "$target" >/dev/null
  else
    codesign --force ${deep_arg:+"$deep_arg"} --timestamp --options runtime --sign "$CODE_SIGN_IDENTITY" "$target" >/dev/null
  fi
}

open_app() {
  /usr/bin/open -n \
    --env "VEILPDF_PROJECT_ROOT=$ROOT_DIR" \
    --env "VEILPDF_REDACTOR=$RUST_BINARY" \
    --env "VEILPDF_HELPER=$HELPER_SCRIPT" \
    --env "VEILPDF_PYTHON=$VEILPDF_PYTHON" \
    "$APP_BUNDLE"
}

build_all

case "$MODE" in
  run)
    open_app
    ;;
  --build-only|build)
    echo "Built $APP_BUNDLE"
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
    pgrep -f "$APP_BINARY" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--build-only|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
