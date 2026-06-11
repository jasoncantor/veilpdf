use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

const DEFAULT_MODEL: &str = "knowledgator/gliner-pii-edge-v1.0";

fn main() {
    if let Err(error) = run() {
        eprintln!("{error}");
        std::process::exit(1);
    }
}

fn run() -> Result<(), String> {
    let cli = Cli::parse(env::args().skip(1).collect())?;
    match cli.command.as_str() {
        "check" => run_check(&cli),
        "redact" => run_redact(&cli),
        _ => Err(usage()),
    }
}

fn run_check(cli: &Cli) -> Result<(), String> {
    let helper = cli.helper_path()?;
    let python = cli.python.clone();
    ensure_file(&helper, "helper")?;

    let mut command = Command::new(&python);
    command
        .arg(&helper)
        .arg("--check")
        .arg("--model")
        .arg(&cli.model)
        .arg("--device")
        .arg(&cli.device)
        .arg("--json");

    if let Some(cache_dir) = cli.cache_dir_arg() {
        command.arg("--cache-dir").arg(cache_dir);
    }
    if cli.download_model {
        command.arg("--download-model");
    }
    if cli.offline {
        command.arg("--offline");
    }

    let output = command
        .output()
        .map_err(|error| format!("failed to start python runtime: {error}"))?;

    if !output.status.success() {
        return Err(command_error("runtime check failed", &output));
    }

    print!("{}", String::from_utf8_lossy(&output.stdout));
    Ok(())
}

fn run_redact(cli: &Cli) -> Result<(), String> {
    let input = cli.input.as_ref().ok_or_else(usage)?.clone();
    let output = cli.output.as_ref().ok_or_else(usage)?.clone();
    let helper = cli.helper_path()?;
    ensure_file(&helper, "helper")?;
    ensure_file(&input, "input PDF")?;

    if let Some(parent) = output.parent() {
        fs::create_dir_all(parent)
            .map_err(|error| format!("failed to create output directory: {error}"))?;
    }

    let labels_json = json_array(&cli.labels);
    let mut command = Command::new(&cli.python);
    command
        .arg(&helper)
        .arg("--input")
        .arg(&input)
        .arg("--output")
        .arg(&output)
        .arg("--model")
        .arg(&cli.model)
        .arg("--device")
        .arg(&cli.device)
        .arg("--threshold")
        .arg(format!("{:.2}", cli.threshold))
        .arg("--detector")
        .arg(&cli.detector)
        .arg("--labels-json")
        .arg(labels_json)
        .arg("--json");

    if let Some(cache_dir) = cli.cache_dir_arg() {
        command.arg("--cache-dir").arg(cache_dir);
    }
    if cli.allow_regex_fallback {
        command.arg("--allow-regex-fallback");
    }

    let result = command
        .output()
        .map_err(|error| format!("failed to start redaction helper: {error}"))?;

    if !result.status.success() {
        return Err(command_error("redaction failed", &result));
    }

    print!("{}", String::from_utf8_lossy(&result.stdout));
    Ok(())
}

#[derive(Debug)]
struct Cli {
    command: String,
    input: Option<PathBuf>,
    output: Option<PathBuf>,
    helper: Option<PathBuf>,
    python: String,
    model: String,
    device: String,
    cache_dir: Option<PathBuf>,
    threshold: f64,
    detector: String,
    labels: Vec<String>,
    allow_regex_fallback: bool,
    download_model: bool,
    offline: bool,
}

impl Cli {
    fn parse(args: Vec<String>) -> Result<Self, String> {
        let mut iter = args.into_iter();
        let command = iter.next().ok_or_else(usage)?;
        let mut cli = Cli {
            command,
            input: None,
            output: None,
            helper: None,
            python: env::var("VEILPDF_PYTHON").unwrap_or_else(|_| "python3".to_string()),
            model: DEFAULT_MODEL.to_string(),
            device: "auto".to_string(),
            cache_dir: env::var("VEILPDF_MODEL_CACHE").ok().map(PathBuf::from),
            threshold: 0.50,
            detector: "gliner".to_string(),
            labels: default_labels(),
            allow_regex_fallback: false,
            download_model: false,
            offline: false,
        };

        while let Some(arg) = iter.next() {
            match arg.as_str() {
                "--input" => cli.input = Some(PathBuf::from(next_value(&mut iter, "--input")?)),
                "--output" => cli.output = Some(PathBuf::from(next_value(&mut iter, "--output")?)),
                "--helper" => cli.helper = Some(PathBuf::from(next_value(&mut iter, "--helper")?)),
                "--python" => cli.python = next_value(&mut iter, "--python")?,
                "--model" => cli.model = next_value(&mut iter, "--model")?,
                "--device" => cli.device = next_value(&mut iter, "--device")?,
                "--cache-dir" => cli.cache_dir = Some(PathBuf::from(next_value(&mut iter, "--cache-dir")?)),
                "--threshold" => {
                    let value = next_value(&mut iter, "--threshold")?;
                    cli.threshold = value
                        .parse::<f64>()
                        .map_err(|_| "invalid --threshold".to_string())?;
                }
                "--detector" => cli.detector = next_value(&mut iter, "--detector")?,
                "--label" => {
                    if cli.labels == default_labels() {
                        cli.labels.clear();
                    }
                    cli.labels.push(next_value(&mut iter, "--label")?);
                }
                "--allow-regex-fallback" => cli.allow_regex_fallback = true,
                "--download-model" => cli.download_model = true,
                "--offline" => cli.offline = true,
                "--json" => {}
                "--help" | "-h" => return Err(usage()),
                unknown => return Err(format!("unknown argument: {unknown}\n{}", usage())),
            }
        }

        if cli.detector != "gliner" && cli.detector != "regex" {
            return Err("--detector must be gliner or regex".to_string());
        }
        if !["auto", "metal", "mps", "cpu"].contains(&cli.device.as_str()) {
            return Err("--device must be auto, metal, mps, or cpu".to_string());
        }
        if !(0.0..=1.0).contains(&cli.threshold) {
            return Err("--threshold must be between 0 and 1".to_string());
        }
        if cli.labels.is_empty() {
            cli.labels = default_labels();
        }

        Ok(cli)
    }

    fn helper_path(&self) -> Result<PathBuf, String> {
        if let Some(helper) = &self.helper {
            return Ok(helper.clone());
        }
        if let Ok(helper) = env::var("VEILPDF_HELPER") {
            return Ok(PathBuf::from(helper));
        }
        Ok(PathBuf::from("scripts/gliner_pii_redactor.py"))
    }

    fn cache_dir_arg(&self) -> Option<String> {
        self.cache_dir
            .as_ref()
            .map(|path| path.display().to_string())
    }
}

fn next_value(iter: &mut impl Iterator<Item = String>, flag: &str) -> Result<String, String> {
    iter.next()
        .ok_or_else(|| format!("{flag} requires a value"))
}

fn ensure_file(path: &Path, label: &str) -> Result<(), String> {
    if path.is_file() {
        Ok(())
    } else {
        Err(format!("{label} does not exist: {}", path.display()))
    }
}

fn command_error(prefix: &str, output: &std::process::Output) -> String {
    let stderr = String::from_utf8_lossy(&output.stderr);
    let stdout = String::from_utf8_lossy(&output.stdout);
    let details = if stderr.trim().is_empty() {
        stdout.trim()
    } else {
        stderr.trim()
    };
    format!("{prefix}: {details}")
}

fn json_array(values: &[String]) -> String {
    let escaped = values
        .iter()
        .map(|value| format!("\"{}\"", json_escape(value)))
        .collect::<Vec<_>>()
        .join(",");
    format!("[{escaped}]")
}

fn json_escape(value: &str) -> String {
    let mut escaped = String::new();
    for ch in value.chars() {
        match ch {
            '"' => escaped.push_str("\\\""),
            '\\' => escaped.push_str("\\\\"),
            '\n' => escaped.push_str("\\n"),
            '\r' => escaped.push_str("\\r"),
            '\t' => escaped.push_str("\\t"),
            _ => escaped.push(ch),
        }
    }
    escaped
}

fn default_labels() -> Vec<String> {
    [
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
    .iter()
    .map(|label| label.to_string())
    .collect()
}

fn usage() -> String {
    "usage:
  hide-pii-redactor check --helper <path> [--python <path>] [--model <id>] [--device auto|metal|mps|cpu] [--cache-dir <path>] [--download-model] [--offline] --json
  hide-pii-redactor redact --input <pdf> --output <pdf> --helper <path> [--python <path>] [--model <id>] [--device auto|metal|mps|cpu] [--cache-dir <path>] [--threshold 0.50] [--detector gliner|regex] [--label <label>] [--allow-regex-fallback] --json"
        .to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn escapes_json_strings() {
        assert_eq!(
            json_array(&["a\"b".to_string(), "c\\d".to_string()]),
            "[\"a\\\"b\",\"c\\\\d\"]"
        );
    }

    #[test]
    fn parses_redact_command() {
        let cli = Cli::parse(vec![
            "redact".to_string(),
            "--input".to_string(),
            "in.pdf".to_string(),
            "--output".to_string(),
            "out.pdf".to_string(),
            "--detector".to_string(),
            "regex".to_string(),
            "--label".to_string(),
            "email".to_string(),
        ])
        .unwrap();
        assert_eq!(cli.detector, "regex");
        assert_eq!(cli.labels, vec!["email"]);
    }

    #[test]
    fn parses_cache_dir_and_model_download() {
        let cli = Cli::parse(vec![
            "check".to_string(),
            "--cache-dir".to_string(),
            "/tmp/models".to_string(),
            "--device".to_string(),
            "metal".to_string(),
            "--download-model".to_string(),
        ])
        .unwrap();
        assert_eq!(cli.cache_dir_arg(), Some("/tmp/models".to_string()));
        assert_eq!(cli.device, "metal");
        assert!(cli.download_model);
        assert!(!cli.offline);
    }
}
