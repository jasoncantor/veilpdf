import Foundation

enum AppSupportPaths {
    static var applicationSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("VeilPDF", isDirectory: true)
    }

    static var runtimeDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("Runtime", isDirectory: true)
    }

    static var runtimeVirtualEnvironment: URL {
        runtimeDirectory.appendingPathComponent("venv", isDirectory: true)
    }

    static var runtimePython: URL {
        runtimeVirtualEnvironment.appendingPathComponent("bin/python")
    }

    static var modelCacheDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("ModelCache", isDirectory: true)
    }

    static var bundledRuntimePayloadDirectory: URL? {
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        let candidate = resourceURL.appendingPathComponent("RuntimePayload", isDirectory: true)
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }

    static var bundledWheelhouseDirectory: URL? {
        guard let payload = bundledRuntimePayloadDirectory else { return nil }
        let candidate = payload.appendingPathComponent("wheels", isDirectory: true)
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }

    static var bundledModelCacheDirectory: URL? {
        guard let payload = bundledRuntimePayloadDirectory else { return nil }
        let candidate = payload.appendingPathComponent("ModelCache", isDirectory: true)
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }
}
