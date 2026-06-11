import AppKit
import Foundation

@MainActor
final class RedactionStore: ObservableObject {
    @Published var jobs: [RedactionJob] = []
    @Published var selectedJobID: RedactionJob.ID?
    @Published var settings: RedactionSettings {
        didSet {
            saveSettings()
            if oldValue.outputFolder != settings.outputFolder {
                refreshQueuedOutputURLs()
            }
        }
    }
    @Published var runtimeCheck: RuntimeCheck?
    @Published var isCheckingRuntime = false
    @Published var isInstallingRuntime = false
    @Published var runtimeInstallMessage = ""
    @Published var isCheckingForUpdates = false
    @Published var updateInfo: UpdateInfo?
    @Published var updateMessage = ""
    @Published var isRedacting = false
    @Published var bannerMessage = "Add PDFs to redact detected PII into black boxes."

    private static let settingsKey = "dev.local.VeilPDF.redactionSettings"
    private let client: RustRedactorClient
    private let runtimeInstaller: RuntimeInstaller
    private let updateService: UpdateService

    init(
        client: RustRedactorClient = RustRedactorClient(),
        runtimeInstaller: RuntimeInstaller = RuntimeInstaller(),
        updateService: UpdateService = UpdateService()
    ) {
        self.client = client
        self.runtimeInstaller = runtimeInstaller
        self.updateService = updateService
        self.settings = Self.loadSettings()
    }

    var selectedJob: RedactionJob? {
        guard let selectedJobID else { return jobs.first }
        return jobs.first { $0.id == selectedJobID }
    }

    var canRedact: Bool {
        !isRedacting && jobs.contains { $0.status == .queued || $0.status == .failed }
    }

    func presentImportPanel() {
        let panel = NSOpenPanel()
        panel.title = "Choose PDFs"
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            Task { @MainActor in
                self?.addPDFs(panel.urls)
            }
        }
    }

    func presentOutputFolderPanel() {
        let panel = NSOpenPanel()
        panel.title = "Choose Output Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.urls.first else { return }
            Task { @MainActor in
                self?.settings.outputFolder = url
            }
        }
    }

    func addPDFs(_ urls: [URL]) {
        let pdfs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
        let existing = Set(jobs.map(\.inputURL))
        let newJobs = pdfs
            .filter { !existing.contains($0) }
            .map { RedactionJob(inputURL: $0, outputURL: defaultOutputURL(for: $0)) }

        jobs.append(contentsOf: newJobs)
        if selectedJobID == nil {
            selectedJobID = jobs.first?.id
        }
        bannerMessage = newJobs.isEmpty ? "No new PDFs were added." : "Added \(newJobs.count) PDF\(newJobs.count == 1 ? "" : "s")."
    }

    func removeSelectedJob() {
        guard let selectedJobID else { return }
        jobs.removeAll { $0.id == selectedJobID }
        self.selectedJobID = jobs.first?.id
    }

    func clearFinished() {
        jobs.removeAll { $0.status == .complete }
        selectedJobID = jobs.first?.id
    }

    func checkRuntime() async {
        isCheckingRuntime = true
        defer { isCheckingRuntime = false }

        do {
            runtimeCheck = try await client.checkRuntime(settings: settings)
            if runtimeCheck?.glinerAvailable == true {
                bannerMessage = "GLiNER runtime is ready."
            } else {
                bannerMessage = "GLiNER is not installed. Regex test mode and fallback remain available."
            }
        } catch {
            bannerMessage = error.localizedDescription
        }
    }

    func installRuntime() async {
        guard !isInstallingRuntime else { return }
        isInstallingRuntime = true
        runtimeInstallMessage = "Starting GLiNER runtime install"
        defer { isInstallingRuntime = false }

        do {
            let result = try await runtimeInstaller.install(settings: settings) { [weak self] message in
                self?.runtimeInstallMessage = message
                self?.bannerMessage = message
            }
            settings.pythonPath = result.pythonPath
            runtimeCheck = result.runtimeCheck
            runtimeInstallMessage = "GLiNER runtime and model are ready."
            bannerMessage = runtimeInstallMessage
        } catch {
            runtimeInstallMessage = error.localizedDescription
            bannerMessage = error.localizedDescription
        }
    }

    func checkForUpdates(openIfAvailable: Bool = false) async {
        guard !isCheckingForUpdates else { return }
        isCheckingForUpdates = true
        updateMessage = "Checking for updates"
        defer { isCheckingForUpdates = false }

        do {
            let info = try await updateService.checkForUpdates(currentVersion: currentVersion)
            updateInfo = info
            if info.isUpdateAvailable {
                updateMessage = "VeilPDF \(info.latestVersion) is available."
                bannerMessage = updateMessage
                if openIfAvailable {
                    openUpdate(info)
                }
            } else {
                updateMessage = "VeilPDF is up to date."
                bannerMessage = updateMessage
            }
        } catch {
            updateMessage = error.localizedDescription
            bannerMessage = error.localizedDescription
        }
    }

    func openAvailableUpdate() {
        guard let updateInfo else { return }
        openUpdate(updateInfo)
    }

    func redactPending() async {
        guard canRedact else { return }
        isRedacting = true
        defer { isRedacting = false }

        for id in jobs.filter({ $0.status == .queued || $0.status == .failed }).map(\.id) {
            guard let index = jobs.firstIndex(where: { $0.id == id }) else { continue }
            jobs[index].status = .running
            jobs[index].message = "Analyzing PDF"
            selectedJobID = id

            do {
                let result = try await client.redact(job: jobs[index], settings: settings)
                jobs[index].status = .complete
                jobs[index].detector = result.detector
                jobs[index].redactionCount = result.redactions
                jobs[index].message = result.warnings.isEmpty
                    ? "Redacted \(result.redactions) match\(result.redactions == 1 ? "" : "es") in \(result.pages) page\(result.pages == 1 ? "" : "s")."
                    : result.warnings.joined(separator: " ")
                jobs[index].completedAt = Date()
                bannerMessage = "Saved \(jobs[index].outputURL.lastPathComponent)."
            } catch {
                jobs[index].status = .failed
                jobs[index].message = error.localizedDescription
                bannerMessage = error.localizedDescription
            }
        }
    }

    func revealSelectedOutput() {
        guard let outputURL = selectedJob?.outputURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([outputURL])
    }

    private func refreshQueuedOutputURLs() {
        for index in jobs.indices where jobs[index].status == .queued {
            jobs[index].outputURL = defaultOutputURL(for: jobs[index].inputURL)
        }
    }

    private func defaultOutputURL(for inputURL: URL) -> URL {
        let folder = settings.outputFolder ?? inputURL.deletingLastPathComponent()
        let base = inputURL.deletingPathExtension().lastPathComponent
        return folder.appendingPathComponent("\(base)-redacted.pdf")
    }

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    private func openUpdate(_ info: UpdateInfo) {
        NSWorkspace.shared.open(info.assetURL ?? info.releaseURL)
    }

    private static func loadSettings() -> RedactionSettings {
        guard
            let data = UserDefaults.standard.data(forKey: settingsKey),
            var settings = try? JSONDecoder().decode(RedactionSettings.self, from: data)
        else {
            return RedactionSettings()
        }
        let migratedDefaultModel = RedactionSettings.legacyDefaultModelIdentifiers.contains(settings.modelIdentifier)
        if migratedDefaultModel {
            settings.modelIdentifier = RedactionSettings.defaultModelIdentifier
        }
        settings.migrateLegacyLabels()
        if migratedDefaultModel, settings.labels.count == RedactionSettings.defaultLabels.count {
            settings.labels = RedactionSettings.defaultLabels
        }
        settings.normalizeLabels()
        return settings
    }

    private func saveSettings() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: Self.settingsKey)
    }
}
