#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-dev}"
APP_NAME="VeilPDF"
CODE_SIGN_IDENTITY="${VEILPDF_CODESIGN_IDENTITY:-}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
ARTIFACTS_DIR="$ROOT_DIR/artifacts"
DMG_PATH="$ARTIFACTS_DIR/$APP_NAME-$VERSION.dmg"
STAGING_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "missing app bundle: $APP_BUNDLE" >&2
  echo "run ./script/build_and_run.sh --build-only first" >&2
  exit 1
fi

mkdir -p "$ARTIFACTS_DIR"
cp -R "$APP_BUNDLE" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -fs HFS+ \
  -ov \
  -format UDZO \
  "$DMG_PATH"

if [[ -n "$CODE_SIGN_IDENTITY" && "$CODE_SIGN_IDENTITY" != "-" ]]; then
  codesign --force --timestamp --sign "$CODE_SIGN_IDENTITY" "$DMG_PATH" >/dev/null
fi

echo "Packaged $DMG_PATH"
