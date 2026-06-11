#!/usr/bin/env python3
"""GLiNER/PyMuPDF PDF redaction helper used by the Rust CLI."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

DEFAULT_MODEL = "knowledgator/gliner-pii-edge-v1.0"
DEFAULT_LABELS = [
    "name",
    "organization",
    "email address",
    "phone number",
    "location address",
    "ssn",
    "credit card",
    "bank account",
    "dob",
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
    (("email address", "email"), re.compile(r"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b", re.IGNORECASE)),
    (("ssn", "social security number"), re.compile(r"\b\d{3}-\d{2}-\d{4}\b")),
    (("phone number",), re.compile(r"(?<!\d)(?:\+?1[\s.-]?)?(?:\(?\d{3}\)?[\s.-]?)\d{3}[\s.-]?\d{4}(?!\d)")),
    (("credit card", "credit card number"), re.compile(r"\b(?:\d[ -]*?){13,19}\b")),
    (("ip address",), re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}\b")),
    (("url",), re.compile(r"\bhttps?://[^\s<>)]+", re.IGNORECASE)),
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
    parser.add_argument("--cache-dir", default="")
    parser.add_argument("--threshold", type=float, default=0.50)
    parser.add_argument("--detector", choices=["gliner", "regex"], default="gliner")
    parser.add_argument("--labels-json", default="")
    parser.add_argument("--allow-regex-fallback", action="store_true")
    parser.add_argument("--download-model", action="store_true")
    parser.add_argument("--offline", action="store_true")
    parser.add_argument("--device", choices=["auto", "metal", "mps", "cpu"], default="auto")
    parser.add_argument("--json", action="store_true")
    return parser


def check_environment(args: argparse.Namespace) -> dict[str, Any]:
    configure_model_cache(args.cache_dir, offline=args.offline)
    errors: list[str] = []
    pymupdf_available = True
    gliner_available = True
    model_available = None
    device = None

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

    if gliner_available:
        try:
            device = resolve_torch_device(args.device)
        except Exception as exc:  # noqa: BLE001
            errors.append(f"Acceleration unavailable: {exc}")

    if gliner_available and args.download_model:
        try:
            model = load_gliner_model(args.model, args.device)
            device = str(model.device)
            model_available = True
        except Exception as exc:  # noqa: BLE001
            errors.append(f"GLiNER model unavailable: {exc}")

    return {
        "python": sys.executable,
        "helper": str(Path(__file__).resolve()),
        "pymupdf_available": pymupdf_available,
        "gliner_available": gliner_available,
        "model_available": model_available,
        "model_cache": configured_model_cache(args.cache_dir),
        "default_model": args.model,
        "device": device,
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
    configure_model_cache(args.cache_dir, offline=args.offline)
    labels = parse_labels(args.labels_json)
    warnings: list[str] = []
    detector_used = args.detector

    doc = fitz.open(input_path)
    redaction_count = 0
    entity_count = 0

    gliner_model = None
    if args.detector == "gliner":
        try:
            gliner_model = load_gliner_model(args.model, args.device)
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
            entities = detect_with_regex(text, labels)
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


def load_gliner_model(model_id: str, device_preference: str = "auto") -> Any:
    device = resolve_torch_device(device_preference)
    from gliner import GLiNER

    model = GLiNER.from_pretrained(model_id, map_location="cpu")
    if device != "cpu":
        model.to(device)
    return model


def resolve_torch_device(device_preference: str) -> str:
    preference = (device_preference or "auto").lower()
    if preference in {"auto", "metal", "mps"}:
        os.environ.setdefault("PYTORCH_ENABLE_MPS_FALLBACK", "1")

    import torch

    if preference == "cpu":
        return "cpu"
    if preference not in {"auto", "metal", "mps"}:
        raise ValueError(f"Unsupported acceleration mode: {device_preference}")

    mps_available = hasattr(torch.backends, "mps") and torch.backends.mps.is_available()
    if mps_available:
        return "mps"
    if preference in {"metal", "mps"}:
        raise RuntimeError("Metal acceleration was requested, but PyTorch MPS is not available on this Mac.")
    return "cpu"


def configure_model_cache(cache_dir: str, offline: bool = False) -> None:
    if cache_dir:
        cache_path = Path(cache_dir).expanduser()
        cache_path.mkdir(parents=True, exist_ok=True)
        os.environ.setdefault("HF_HOME", str(cache_path))
        os.environ.setdefault("HF_HUB_CACHE", str(cache_path / "hub"))
        os.environ.setdefault("TRANSFORMERS_CACHE", str(cache_path / "transformers"))
    if offline:
        os.environ["HF_HUB_OFFLINE"] = "1"
        os.environ["TRANSFORMERS_OFFLINE"] = "1"


def configured_model_cache(cache_dir: str) -> str:
    if cache_dir:
        return str(Path(cache_dir).expanduser())
    return ""


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


def detect_with_regex(text: str, labels: list[str]) -> list[Entity]:
    enabled_labels = {label.lower() for label in labels}
    entities: list[Entity] = []
    for aliases, pattern in REGEX_PATTERNS:
        matched_label = next((label for label in aliases if label.lower() in enabled_labels), None)
        if matched_label is None:
            continue
        for match in pattern.finditer(text):
            value = clean_entity_text(match.group(0))
            if value:
                entities.append(Entity(text=value, label=matched_label, score=1.0))
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
