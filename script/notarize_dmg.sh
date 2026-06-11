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

SUBMIT_JSON="$(mktemp)"
cleanup() {
  rm -f "$SUBMIT_JSON"
}
trap cleanup EXIT

xcrun notarytool submit "$DMG_PATH" \
  --keychain-profile "$PROFILE" \
  "${keychain_args[@]}" \
  --wait \
  --output-format json | tee "$SUBMIT_JSON"

SUBMISSION_ID="$(/usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("id", ""))' "$SUBMIT_JSON")"
STATUS="$(/usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("status", ""))' "$SUBMIT_JSON")"

if [[ "$STATUS" != "Accepted" ]]; then
  if [[ -n "$SUBMISSION_ID" ]]; then
    xcrun notarytool log "$SUBMISSION_ID" \
      --keychain-profile "$PROFILE" \
      "${keychain_args[@]}" || true
  fi
  echo "notarization failed with status: ${STATUS:-unknown}" >&2
  exit 1
fi

xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
spctl -a -vv -t open --context context:primary-signature "$DMG_PATH"
