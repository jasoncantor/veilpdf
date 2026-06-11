# VeilPDF

[![CI](https://github.com/jasoncantor/veilpdf/actions/workflows/ci.yml/badge.svg)](https://github.com/jasoncantor/veilpdf/actions/workflows/ci.yml)
[![Release](https://github.com/jasoncantor/veilpdf/actions/workflows/release.yml/badge.svg)](https://github.com/jasoncantor/veilpdf/actions/workflows/release.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

VeilPDF is a macOS app for redacting sensitive information from PDFs before you share them. It runs locally, detects common personally identifiable information with a Mac-friendly GLiNER PII model, and writes a new redacted PDF next to the original file.

## Download

Download the latest signed and notarized DMG from [GitHub Releases](https://github.com/jasoncantor/veilpdf/releases/latest).

1. Open the downloaded `VeilPDF-vX.Y.Z.dmg`.
2. Drag `VeilPDF.app` to Applications.
3. Open VeilPDF.
4. In Settings, click `Install Included Runtime` to install the bundled GLiNER runtime and model locally.
5. Add a PDF with the `+` button or by dragging it into the sidebar.

If macOS blocks an older build, remove that copy and install the latest release from the link above.

## Features

- Detects names, emails, phone numbers, addresses, IDs, credentials, URLs, organizations, and other PII labels.
- Applies real PDF redactions with black filled redaction boxes.
- Lets you choose which PII categories should be redacted.
- Keeps processing local to your Mac.
- Includes a bundled GLiNER runtime payload and Mac-friendly edge model in release builds.
- Installs the included runtime into your user Application Support folder.
- Uses Apple Metal through PyTorch MPS automatically when available, with CPU fallback.
- Checks GitHub Releases for app updates from inside VeilPDF.
- Supports drag-and-drop PDF intake and batch-style job tracking.
- Includes a regex test mode for quick local checks.

## Using VeilPDF

1. Add one or more PDFs.
2. Choose `GLiNER-PII` for model-based detection or `Regex Test Mode` for a quick rule-based pass.
3. Open Settings to choose the PII categories VeilPDF should redact.
4. Click the play button or press `Cmd+R`.
5. Review the new `-redacted.pdf` file before sharing it.

Redacted files are saved next to the original PDF with `-redacted` appended to the filename.

## Runtime

VeilPDF uses a local Python environment for GLiNER PII detection. Release builds include a runtime payload with Python packages and the `knowledgator/gliner-pii-edge-v1.0` model cache. From Settings, click `Install Included Runtime` to create a VeilPDF-managed environment under `~/Library/Application Support/VeilPDF` and install that bundled payload locally.

The default acceleration setting is `Auto (Metal)`. On Apple Silicon Macs, VeilPDF asks PyTorch to use the MPS device, which runs through Apple Metal. You can force `Metal` or `CPU` in Settings.

If you prefer to manage Python yourself, open Settings and point the Python field at an interpreter that already has `PyMuPDF`, `gliner`, and the selected GLiNER model available.

## Updates

Use `VeilPDF > Check for Updates...` or the Updates section in Settings to check the latest GitHub release.

## Build From Source

Requirements:

- macOS 14 or newer.
- Xcode command line tools.
- Rust stable.
- Python 3.11 or newer.

Set up the local GLiNER runtime:

```bash
./scripts/bootstrap_gliner.sh
```

Build and run the app:

```bash
./script/build_and_run.sh
```

Build without launching:

```bash
./script/build_and_run.sh --build-only
```

Run the core checks:

```bash
cargo test --manifest-path RustRedactor/Cargo.toml
swift build --package-path "$PWD"
./script/test_core.sh
```

For contribution guidelines, validation expectations, and privacy rules for sample data, see [CONTRIBUTING.md](CONTRIBUTING.md).

## Privacy

VeilPDF is designed for local document processing. It does not make PDF redaction risk-free: detection quality depends on text extraction, PDF structure, scan quality, and model coverage. Always inspect the redacted output before sharing a document.

## Contributing

Contributions are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.

## License

VeilPDF is released under the [MIT License](LICENSE).
