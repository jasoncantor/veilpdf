#!/usr/bin/env python3
"""Create a synthetic PDF and verify regex-mode redaction removes text."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

import fitz


ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "scripts" / "gliner_pii_redactor.py"
MANIFEST = ROOT / "RustRedactor" / "Cargo.toml"


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        input_pdf = tmp_path / "sample.pdf"
        output_pdf = tmp_path / "sample-redacted.pdf"
        make_pdf(input_pdf)
        detector = os.environ.get("DETECTOR", "regex")
        redactor_python = os.environ.get("REDACTOR_PYTHON", sys.executable)
        threshold = os.environ.get("THRESHOLD", "0.30" if detector == "gliner" else "0.50")
        labels = split_env_list("LABELS")

        command = [
            "cargo",
            "run",
            "--manifest-path",
            str(MANIFEST),
            "--",
            "redact",
            "--input",
            str(input_pdf),
            "--output",
            str(output_pdf),
            "--helper",
            str(HELPER),
            "--python",
            redactor_python,
            "--detector",
            detector,
            "--threshold",
            threshold,
            "--json",
        ]
        for label in labels:
            command.extend(["--label", label])
        completed = subprocess.run(command, check=True, capture_output=True, text=True)
        result = json.loads(completed.stdout)

        redacted_text = extract_text(output_pdf)
        expected_redacted = split_env_list("EXPECT_REDACTED") or ["jane@example.com", "123-45-6789", "555-123-4567"]
        expected_visible = split_env_list("EXPECT_VISIBLE")
        remaining = [value for value in expected_redacted if value in redacted_text]
        if remaining:
            raise AssertionError(f"redacted PDF still contains: {remaining}")
        missing = [value for value in expected_visible if value not in redacted_text]
        if missing:
            raise AssertionError(f"expected PDF text to remain visible: {missing}")
        if result["redactions"] < len(expected_redacted):
            raise AssertionError(f"expected at least {len(expected_redacted)} redactions, got {result['redactions']}")

    print("smoke redaction passed")
    return 0


def make_pdf(path: Path) -> None:
    doc = fitz.open()
    page = doc.new_page(width=612, height=792)
    page.insert_text(
        (72, 96),
        "Patient Jane Doe\nEmail: jane@example.com\nPhone: 555-123-4567\nSSN: 123-45-6789",
        fontsize=12,
    )
    doc.save(path)
    doc.close()


def extract_text(path: Path) -> str:
    doc = fitz.open(path)
    text = "\n".join(page.get_text("text") for page in doc)
    doc.close()
    return text


def split_env_list(name: str) -> list[str]:
    return [value.strip() for value in os.environ.get(name, "").split(",") if value.strip()]


if __name__ == "__main__":
    raise SystemExit(main())
