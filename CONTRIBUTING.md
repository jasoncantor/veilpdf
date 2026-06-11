# Contributing

Thanks for helping improve VeilPDF. This project handles sensitive documents, so changes should favor correctness, local processing, and clear failure modes over convenience.

## Development Setup

1. Install Xcode command line tools, Rust stable, and Python 3.11 or newer.
2. Install the project-local Python runtime:

   ```bash
   ./scripts/bootstrap_gliner.sh
   ```

3. Build the app:

   ```bash
   ./script/build_and_run.sh --build-only
   ```

4. Run the app:

   ```bash
   ./script/build_and_run.sh
   ```

## Validation

Before opening a pull request, run:

```bash
cargo test --manifest-path RustRedactor/Cargo.toml
swift build --package-path "$PWD"
./script/test_core.sh
```

If your change affects PII detection or PDF redaction behavior, inspect the generated output PDF manually as well.
The default smoke test uses regex mode with PyMuPDF so it stays fast. For GLiNER behavior changes, run a manual check with `.venv/bin/python` and inspect the output PDF.

## Pull Request Guidelines

- Keep changes focused and easy to review.
- Include the validation commands you ran.
- Add or update tests for behavior changes.
- Do not commit generated build output, local caches, model downloads, or sample documents with real PII.
- Prefer local/offline processing paths. Do not add remote document upload or telemetry behavior without an explicit design discussion.
- Document user-facing behavior changes in `README.md`.

## Security And Privacy

Do not include real personal data in issues, pull requests, fixtures, screenshots, or logs. Use synthetic examples for testing.

If you find a privacy or security issue, avoid public disclosure of sensitive details until a fix is available.
