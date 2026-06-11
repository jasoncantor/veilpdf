#!/usr/bin/env python3
"""GLiNER/PyMuPDF PDF redaction helper used by the Rust CLI."""

from __future__ import annotations

import argparse
import json
import re
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

DEFAULT_MODEL = "urchade/gliner_multi_pii-v1"
DEFAULT_LABELS = [
    "person",
    "organization",
    "email",
    "phone number",
    "address",
    "social security number",
    "credit card number",
    "bank account number",
    "date of birth",
    "passport number",
    "driver license",
    "medical record number",
    "tax identification number",
    "ip address",
    "username",
    "password",
    "url",
]

REGEX_PATTERNS = [
    ("email", re.compile(r"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b", re.IGNORECASE)),
    ("social security number", re.compile(r"\b\d{3}-\d{2}-\d{4}\b")),
    ("phone number", re.compile(r"(?<!\d)(?:\+?1[\s.-]?)?(?:\(?\d{3}\)?[\s.-]?)\d{3}[\s.-]?\d{4}(?!\d)")),
    ("credit card number", re.compile(r"\b(?:\d[ -]*?){13,19}\b")),
    ("ip address", re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}\b")),
    ("url", re.compile(r"\bhttps?://[^\s<>)]+", re.IGNORECASE)),
]


@dataclass(frozen=True)
class Entity:
    text: str
    label: str
    score: float


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    if args.check:
        print_json(check_environment(args))
        return 0

    try:
        result = redact_pdf(args)
    except Exception as exc:  # noqa: BLE001 - command helper should report cleanly to Rust.
        print(str(exc), file=sys.stderr)
        return 1

    print_json(result)
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Detect PII with GLiNER and apply PDF redactions.")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--input")
    parser.add_argument("--output")
    parser.add_argument("--model", default=DEFAULT_MODEL)
    parser.add_argument("--threshold", type=float, default=0.50)
    parser.add_argument("--detector", choices=["gliner", "regex"], default="gliner")
    parser.add_argument("--labels-json", default="")
    parser.add_argument("--allow-regex-fallback", action="store_true")
    parser.add_argument("--json", action="store_true")
    return parser


def check_environment(args: argparse.Namespace) -> dict[str, Any]:
    errors: list[str] = []
    pymupdf_available = True
    gliner_available = True

    try:
        import fitz  # noqa: F401
    except Exception as exc:  # noqa: BLE001
        pymupdf_available = False
        errors.append(f"PyMuPDF unavailable: {exc}")

    try:
        import gliner  # noqa: F401
    except Exception as exc:  # noqa: BLE001
        gliner_available = False
        errors.append(f"GLiNER unavailable: {exc}")

    return {
        "python": sys.executable,
        "helper": str(Path(__file__).resolve()),
        "pymupdf_available": pymupdf_available,
        "gliner_available": gliner_available,
        "default_model": args.model,
        "errors": errors,
    }


def redact_pdf(args: argparse.Namespace) -> dict[str, Any]:
    if not args.input or not args.output:
        raise ValueError("--input and --output are required")

    try:
        import fitz
    except Exception as exc:  # noqa: BLE001
        raise RuntimeError(f"PyMuPDF is required for PDF redaction: {exc}") from exc

    start = time.monotonic()
    input_path = Path(args.input)
    output_path = Path(args.output)
    labels = parse_labels(args.labels_json)
    warnings: list[str] = []
    detector_used = args.detector

    doc = fitz.open(input_path)
    redaction_count = 0
    entity_count = 0

    gliner_model = None
    if args.detector == "gliner":
        try:
            gliner_model = load_gliner_model(args.model)
        except Exception as exc:  # noqa: BLE001
            if not args.allow_regex_fallback:
                raise RuntimeError(f"GLiNER could not be loaded: {exc}") from exc
            detector_used = "regex-fallback"
            warnings.append(f"GLiNER unavailable; used regex fallback. {exc}")

    for page_index in range(doc.page_count):
        page = doc[page_index]
        text = page.get_text("text", sort=True)
        if not text.strip():
            continue

        if args.detector == "regex" or detector_used == "regex-fallback":
            entities = detect_with_regex(text)
        else:
            entities = detect_with_gliner(gliner_model, text, labels, args.threshold)

        entities = dedupe_entities(entities)
        entity_count += len(entities)
        redaction_count += add_page_redactions(page, entities)

    for page in doc:
        if page.first_annot:
            page.apply_redactions(images=fitz.PDF_REDACT_IMAGE_PIXELS)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    doc.save(output_path, garbage=4, deflate=True, clean=True)
    doc.close()

    return {
        "input": str(input_path),
        "output": str(output_path),
        "detector": detector_used,
        "redactions": redaction_count,
        "entities": entity_count,
        "pages": len(fitz.open(output_path)),
        "elapsed_ms": int((time.monotonic() - start) * 1000),
        "warnings": warnings,
    }


def load_gliner_model(model_id: str) -> Any:
    from gliner import GLiNER

    return GLiNER.from_pretrained(model_id)


def detect_with_gliner(model: Any, text: str, labels: list[str], threshold: float) -> list[Entity]:
    entities: list[Entity] = []
    for chunk in chunk_text(text):
        predictions = model.predict_entities(chunk, labels, threshold=threshold)
        for prediction in predictions:
            value = clean_entity_text(str(prediction.get("text", "")))
            if value:
                entities.append(
                    Entity(
                        text=value,
                        label=str(prediction.get("label", "pii")),
                        score=float(prediction.get("score", threshold)),
                    )
                )
    return entities


def detect_with_regex(text: str) -> list[Entity]:
    entities: list[Entity] = []
    for label, pattern in REGEX_PATTERNS:
        for match in pattern.finditer(text):
            value = clean_entity_text(match.group(0))
            if value:
                entities.append(Entity(text=value, label=label, score=1.0))
    return entities


def add_page_redactions(page: Any, entities: list[Entity]) -> int:
    count = 0
    for entity in entities:
        for needle in search_variants(entity.text):
            rects = page.search_for(needle)
            if not rects:
                continue
            for rect in rects:
                padded = pad_rect(rect, 1.0)
                page.add_redact_annot(padded, text="", fill=(0, 0, 0))
                count += 1
            break
    return count


def search_variants(text: str) -> list[str]:
    compact = clean_entity_text(text)
    variants = [compact]
    if "\n" in text or "  " in text:
        variants.append(" ".join(text.split()))
    if "-" in compact:
        variants.append(compact.replace("-", " "))
    return list(dict.fromkeys(value for value in variants if len(value) >= 2))


def pad_rect(rect: Any, amount: float) -> Any:
    import fitz

    padded = fitz.Rect(rect)
    padded.x0 -= amount
    padded.y0 -= amount
    padded.x1 += amount
    padded.y1 += amount
    return padded


def parse_labels(raw: str) -> list[str]:
    if not raw:
        return DEFAULT_LABELS
    labels = json.loads(raw)
    if not isinstance(labels, list):
        return DEFAULT_LABELS
    cleaned = [str(label).strip() for label in labels if str(label).strip()]
    return cleaned or DEFAULT_LABELS


def clean_entity_text(text: str) -> str:
    return " ".join(text.split()).strip(" ,;:.")


def dedupe_entities(entities: list[Entity]) -> list[Entity]:
    seen: set[tuple[str, str]] = set()
    unique: list[Entity] = []
    for entity in sorted(entities, key=lambda item: len(item.text), reverse=True):
        key = (entity.text.lower(), entity.label.lower())
        if key in seen:
            continue
        seen.add(key)
        unique.append(entity)
    return unique


def chunk_text(text: str, max_chars: int = 3500, overlap: int = 250) -> list[str]:
    if len(text) <= max_chars:
        return [text]

    chunks: list[str] = []
    start = 0
    while start < len(text):
        end = min(start + max_chars, len(text))
        if end < len(text):
            boundary = text.rfind("\n", start, end)
            if boundary > start + 500:
                end = boundary
        chunks.append(text[start:end])
        if end == len(text):
            break
        start = max(end - overlap, start + 1)
    return chunks


def print_json(value: dict[str, Any]) -> None:
    print(json.dumps(value, ensure_ascii=False, separators=(",", ":")))


if __name__ == "__main__":
    raise SystemExit(main())
