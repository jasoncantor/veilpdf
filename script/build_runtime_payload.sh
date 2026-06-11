#!/usr/bin/env bash
set -euo pipefail

MODEL_ID="${VEILPDF_GLINER_MODEL:-knowledgator/gliner-pii-edge-v1.0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
PAYLOAD_DIR="$DIST_DIR/RuntimePayload"
WHEEL_DIR="$PAYLOAD_DIR/wheels"
MODEL_CACHE_DIR="$PAYLOAD_DIR/ModelCache"
BUILD_VENV="$DIST_DIR/runtime-build-venv"
CODESIGN_IDENTITY="${VEILPDF_CODESIGN_IDENTITY:-}"
if [[ -z "${PYTHON:-}" ]]; then
  PYTHON="$(command -v python3 || command -v python3.12 || command -v python3.11 || true)"
fi

if [[ -z "${PYTHON:-}" ]]; then
  echo "python3 was not found" >&2
  exit 1
fi

rm -rf "$PAYLOAD_DIR" "$BUILD_VENV"
mkdir -p "$WHEEL_DIR" "$MODEL_CACHE_DIR"
trap 'rm -rf "$BUILD_VENV"' EXIT

sign_wheelhouse() {
  if [[ -z "$CODESIGN_IDENTITY" || "$CODESIGN_IDENTITY" == "-" ]]; then
    return
  fi

  local signing_dir="$DIST_DIR/wheel-signing"
  rm -rf "$signing_dir"
  mkdir -p "$signing_dir"

  for wheel in "$WHEEL_DIR"/*.whl; do
    [[ -e "$wheel" ]] || continue

    local wheel_dir="$signing_dir/$(basename "$wheel" .whl)"
    rm -rf "$wheel_dir"
    mkdir -p "$wheel_dir"
    "$BUILD_VENV/bin/python" -m wheel unpack "$wheel" --dest "$wheel_dir" >/dev/null

    local unpacked_dir
    unpacked_dir="$(find "$wheel_dir" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
    [[ -n "$unpacked_dir" ]] || continue

    local signed_any=0
    while IFS= read -r -d '' candidate; do
      if file "$candidate" | grep -q "Mach-O"; then
        codesign --force --timestamp --options runtime --sign "$CODESIGN_IDENTITY" "$candidate" >/dev/null
        signed_any=1
      fi
    done < <(find "$unpacked_dir" -type f -print0)

    if [[ "$signed_any" == "1" ]]; then
      rm "$wheel"
      "$BUILD_VENV/bin/python" -m wheel pack "$unpacked_dir" --dest-dir "$WHEEL_DIR" >/dev/null
    fi
  done

  rm -rf "$signing_dir"
}

"$PYTHON" -m venv "$BUILD_VENV"
"$BUILD_VENV/bin/python" -m ensurepip --upgrade
"$BUILD_VENV/bin/python" -m pip install --upgrade pip
"$BUILD_VENV/bin/python" -m pip install --upgrade wheel
"$BUILD_VENV/bin/python" -m pip download --dest "$WHEEL_DIR" PyMuPDF gliner
sign_wheelhouse
"$BUILD_VENV/bin/python" -m pip install --no-index --find-links "$WHEEL_DIR" PyMuPDF gliner
"$BUILD_VENV/bin/python" "$ROOT_DIR/scripts/gliner_pii_redactor.py" \
  --check \
  --model "$MODEL_ID" \
  --cache-dir "$MODEL_CACHE_DIR" \
  --download-model \
  --json
"$BUILD_VENV/bin/python" "$ROOT_DIR/scripts/gliner_pii_redactor.py" \
  --check \
  --model "$MODEL_ID" \
  --cache-dir "$MODEL_CACHE_DIR" \
  --download-model \
  --offline \
  --json

cat >"$PAYLOAD_DIR/runtime-manifest.json" <<JSON
{
  "model": "$MODEL_ID",
  "wheelhouse": "wheels",
  "model_cache": "ModelCache"
}
JSON

echo "Built bundled runtime payload at $PAYLOAD_DIR"
