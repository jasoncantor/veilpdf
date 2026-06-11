#!/usr/bin/env bash
set -euo pipefail

DMG_PATH="${1:?usage: script/notarize_dmg.sh <path-to-dmg>}"
PROFILE="${VEILPDF_NOTARY_PROFILE:?set VEILPDF_NOTARY_PROFILE to a notarytool keychain profile name}"
KEYCHAIN="${VEILPDF_NOTARY_KEYCHAIN:-}"

if [[ ! -f "$DMG_PATH" ]]; then
  echo "missing DMG: $DMG_PATH" >&2
  exit 1
fi

keychain_args=()
if [[ -n "$KEYCHAIN" ]]; then
  keychain_args=(--keychain "$KEYCHAIN")
fi

xcrun notarytool submit "$DMG_PATH" \
  --keychain-profile "$PROFILE" \
  "${keychain_args[@]}" \
  --wait

xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
spctl -a -vv -t open --context context:primary-signature "$DMG_PATH"
