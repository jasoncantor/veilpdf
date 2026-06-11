import Foundation

enum RedactorClientError: LocalizedError {
    case missingBinary(String)
    case processFailed(String)
    case invalidOutput(String)

    var errorDescription: String? {
        switch self {
        case .missingBinary(let path):
            "Rust redactor was not found at \(path). Run ./script/build_and_run.sh --build-only first."
        case .processFailed(let message):
            message
        case .invalidOutput(let output):
            "The redactor returned invalid output: \(output)"
        }
    }
}

struct RustRedactorClient {
    func checkRuntime(settings: RedactionSettings) async throws -> RuntimeCheck {
        let paths = ProjectPaths.resolve(settings: settings)
        let output = try await runRedactor(
            at: paths.redactor,
            arguments: [
                "check",
                "--helper", paths.helper.path,
                "--python", paths.python,
                "--model", settings.modelIdentifier,
                "--json"
            ]
        )
        return try decode(RuntimeCheck.self, from: output)
    }

    func redact(job: RedactionJob, settings: RedactionSettings) async throws -> RedactionResult {
        let paths = ProjectPaths.resolve(settings: settings)
        var arguments = [
            "redact",
            "--input", job.inputURL.path,
            "--output", job.outputURL.path,
            "--helper", paths.helper.path,
            "--python", paths.python,
            "--model", settings.modelIdentifier,
            "--threshold", String(format: "%.2f", settings.threshold),
            "--detector", settings.detectorMode.rawValue,
            "--json"
        ]
        for label in settings.labels {
            arguments.append(contentsOf: ["--label", label])
        }
        if settings.allowRegexFallback {
            arguments.append("--allow-regex-fallback")
        }

        let output = try await runRedactor(at: paths.redactor, arguments: arguments)
        return try decode(RedactionResult.self, from: output)
    }

    private func decode<T: Decodable>(_ type: T.Type, from output: String) throws -> T {
        guard let data = output.data(using: .utf8) else {
            throw RedactorClientError.invalidOutput(output)
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw RedactorClientError.invalidOutput(output)
        }
    }

    private func runRedactor(at executableURL: URL, arguments: [String]) async throws -> String {
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw RedactorClientError.missingBinary(executableURL.path)
        }

        return try await Task.detached(priority: .userInitiated) {
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()
            process.executableURL = executableURL
            process.arguments = arguments
            process.standardOutput = stdout
            process.standardError = stderr

            try process.run()
            let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
            let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            let output = String(data: outputData, encoding: .utf8) ?? ""
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
            guard process.terminationStatus == 0 else {
                let message = errorOutput.isEmpty ? output : errorOutput
                throw RedactorClientError.processFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        }.value
    }
}

private struct ProjectPaths {
    let root: URL
    let redactor: URL
    let helper: URL
    let python: String

    static func resolve(settings: RedactionSettings) -> ProjectPaths {
        let environment = ProcessInfo.processInfo.environment
        let root = environment["VEILPDF_PROJECT_ROOT"].map(URL.init(fileURLWithPath:)) ?? inferProjectRoot()
        let redactor = environment["VEILPDF_REDACTOR"].map(URL.init(fileURLWithPath:))
            ?? bundledRedactor()
            ?? root.appendingPathComponent("RustRedactor/target/debug/hide-pii-redactor")
        let helper = environment["VEILPDF_HELPER"].map(URL.init(fileURLWithPath:))
            ?? bundledHelper()
            ?? root.appendingPathComponent("scripts/gliner_pii_redactor.py")
        let python = !settings.pythonPath.isEmpty
            ? settings.pythonPath
            : environment["VEILPDF_PYTHON"] ?? defaultPythonPath(root: root)

        return ProjectPaths(root: root, redactor: redactor, helper: helper, python: python)
    }

    private static func bundledRedactor() -> URL? {
        let candidate = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/hide-pii-redactor")
        if FileManager.default.isExecutableFile(atPath: candidate.path) {
            return candidate
        }
        return nil
    }

    private static func bundledHelper() -> URL? {
        let candidate = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/gliner_pii_redactor.py")
        if FileManager.default.isReadableFile(atPath: candidate.path) {
            return candidate
        }
        return nil
    }

    private static func inferProjectRoot() -> URL {
        let bundleURL = Bundle.main.bundleURL
        let distParent = bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: distParent.appendingPathComponent("Package.swift").path) {
            return distParent
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    private static func defaultPythonPath(root: URL) -> String {
        let projectVenv = root.appendingPathComponent(".venv/bin/python").path
        for candidate in [projectVenv, "/opt/homebrew/bin/python3", "/opt/homebrew/bin/python3.12", "/opt/homebrew/bin/python3.11", "/usr/bin/python3"] {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return "python3"
    }

}
