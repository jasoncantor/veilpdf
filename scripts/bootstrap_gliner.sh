#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON="${PYTHON:-$(command -v python3 || command -v python3.12 || command -v python3.11)}"
VENV="$ROOT_DIR/.venv"

venv_ready() {
  [[ -x "$VENV/bin/python" ]] &&
    "$VENV/bin/python" -m pip --version >/dev/null 2>&1 &&
    "$VENV/bin/python" -c 'import fitz, gliner' >/dev/null 2>&1
}

if [[ -d "$VENV" ]] && ! venv_ready; then
  BACKUP="$ROOT_DIR/.venv.broken-$(date +%Y%m%d%H%M%S)"
  echo "Moving incomplete venv to $BACKUP"
  mv "$VENV" "$BACKUP"
fi

"$PYTHON" -m venv "$VENV"
"$VENV/bin/python" -m ensurepip --upgrade
"$VENV/bin/python" -m pip install --upgrade pip
"$VENV/bin/python" -m pip install PyMuPDF gliner

cat <<EOF
GLiNER runtime installed.
Use this Python path in app settings:
$VENV/bin/python
EOF
