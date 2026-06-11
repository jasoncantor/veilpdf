import AppKit
import Foundation

@MainActor
final class RedactionStore: ObservableObject {
    @Published var jobs: [RedactionJob] = []
    @Published var selectedJobID: RedactionJob.ID?
    @Published var settings = RedactionSettings()
    @Published var runtimeCheck: RuntimeCheck?
    @Published var isCheckingRuntime = false
    @Published var isRedacting = false
    @Published var bannerMessage = "Add PDFs to redact detected PII into black boxes."

    private let client: RustRedactorClient

    init(client: RustRedactorClient = RustRedactorClient()) {
        self.client = client
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
                self?.refreshQueuedOutputURLs()
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
}
