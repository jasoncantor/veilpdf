import Foundation

enum RuntimeInstallerError: LocalizedError {
    case pythonUnavailable
    case processFailed(String)
    case runtimeUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .pythonUnavailable:
            "Python 3 was not found. Install Python 3, then try installing the GLiNER runtime again."
        case .processFailed(let message):
            message
        case .runtimeUnavailable(let message):
            message
        }
    }
}

struct RuntimeInstallationResult {
    let pythonPath: String
    let runtimeCheck: RuntimeCheck
}

struct RuntimeInstaller {
    private let client: RustRedactorClient

    init(client: RustRedactorClient = RustRedactorClient()) {
        self.client = client
    }

    func install(settings: RedactionSettings, progress: @escaping @MainActor @Sendable (String) -> Void) async throws -> RuntimeInstallationResult {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: AppSupportPaths.runtimeDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: AppSupportPaths.modelCacheDirectory, withIntermediateDirectories: true)

        let bundledWheelhouse = AppSupportPaths.bundledWheelhouseDirectory
        let bundledModelCache = AppSupportPaths.bundledModelCacheDirectory

        let basePython = try resolveBasePython(settings: settings)
        await progress("Creating Python environment")
        try await run(executable: basePython, arguments: ["-m", "venv", AppSupportPaths.runtimeVirtualEnvironment.path])

        let runtimePython = AppSupportPaths.runtimePython
        guard fileManager.isExecutableFile(atPath: runtimePython.path) else {
            throw RuntimeInstallerError.runtimeUnavailable("The Python environment was created but no executable was found at \(runtimePython.path).")
        }

        await progress("Preparing pip")
        do {
            try await run(executable: runtimePython, arguments: ["-m", "ensurepip", "--upgrade"])
        } catch {
            try await run(executable: runtimePython, arguments: ["-m", "pip", "--version"])
        }

        await progress("Updating pip")
        try await run(executable: runtimePython, arguments: ["-m", "pip", "install", "--upgrade", "pip"])

        if let bundledWheelhouse {
            await progress("Installing included GLiNER packages")
            do {
                try await run(
                    executable: runtimePython,
                    arguments: [
                        "-m", "pip", "install",
                        "--no-index",
                        "--find-links", bundledWheelhouse.path,
                        "--upgrade",
                        "PyMuPDF",
                        "gliner",
                    ]
                )
            } catch {
                await progress("Downloading compatible GLiNER packages")
                try await run(
                    executable: runtimePython,
                    arguments: [
                        "-m", "pip", "install",
                        "--find-links", bundledWheelhouse.path,
                        "--upgrade",
                        "PyMuPDF",
                        "gliner",
                    ]
                )
            }
        } else {
            await progress("Downloading GLiNER packages")
            try await run(executable: runtimePython, arguments: ["-m", "pip", "install", "--upgrade", "PyMuPDF", "gliner"])
        }

        if let bundledModelCache {
            await progress("Installing included GLiNER-PII model")
            try copyDirectoryContents(from: bundledModelCache, to: AppSupportPaths.modelCacheDirectory)
        }

        await progress(bundledModelCache == nil ? "Downloading GLiNER-PII model" : "Verifying included GLiNER-PII model")
        var installedSettings = settings
        installedSettings.pythonPath = runtimePython.path
        let check = try await client.downloadModel(settings: installedSettings, offline: bundledModelCache != nil)
        guard check.glinerAvailable, check.modelAvailable == true else {
            let message = check.errors.isEmpty ? "GLiNER runtime installed, but the model could not be loaded." : check.errors.joined(separator: " ")
            throw RuntimeInstallerError.runtimeUnavailable(message)
        }

        await progress("GLiNER runtime is ready")
        return RuntimeInstallationResult(pythonPath: runtimePython.path, runtimeCheck: check)
    }

    private func resolveBasePython(settings: RedactionSettings) throws -> URL {
        let managedRuntime = AppSupportPaths.runtimePython.path
        let candidates = [
            settings.pythonPath,
            ProcessInfo.processInfo.environment["VEILPDF_PYTHON"] ?? "",
            "/opt/homebrew/bin/python3",
            "/opt/homebrew/bin/python3.12",
            "/opt/homebrew/bin/python3.11",
            "/usr/local/bin/python3",
            "/usr/bin/python3",
            "python3",
        ]
        .filter { !$0.isEmpty && $0 != managedRuntime }

        for candidate in candidates {
            if let resolved = resolveExecutable(candidate) {
                return resolved
            }
        }

        throw RuntimeInstallerError.pythonUnavailable
    }

    private func copyDirectoryContents(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        let items = try fileManager.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: nil,
            options: []
        )

        for item in items {
            let target = destination.appendingPathComponent(item.lastPathComponent)
            if fileManager.fileExists(atPath: target.path) {
                try fileManager.removeItem(at: target)
            }
            try fileManager.copyItem(at: item, to: target)
        }
    }

    private func resolveExecutable(_ command: String) -> URL? {
        let fileManager = FileManager.default
        if command.contains("/") {
            return fileManager.isExecutableFile(atPath: command) ? URL(fileURLWithPath: command) : nil
        }

        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        for directory in path.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent(command)
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    @discardableResult
    private func run(executable: URL, arguments: [String]) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()
            process.executableURL = executable
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
                throw RuntimeInstallerError.processFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        }.value
    }
}
