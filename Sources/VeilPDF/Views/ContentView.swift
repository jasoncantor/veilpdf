import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var store: RedactionStore
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                sidebar
                    .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 420)
            } detail: {
                DetailView(job: store.selectedJob)
            }

            Divider()
            StatusBarView()
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    store.presentImportPanel()
                } label: {
                    Label("Add PDFs", systemImage: "plus")
                }

                Button {
                    Task { await store.redactPending() }
                } label: {
                    Label("Start Redaction", systemImage: "play.fill")
                }
                .disabled(!store.canRedact)

                Button {
                    store.revealSelectedOutput()
                } label: {
                    Label("Reveal Output", systemImage: "folder")
                }
                .disabled(store.selectedJob?.status != .complete)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop(providers:))
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            if store.jobs.isEmpty {
                DropZoneView(isTargeted: isDropTargeted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $store.selectedJobID) {
                    ForEach(store.jobs) { job in
                        JobRowView(job: job)
                            .tag(job.id as RedactionJob.ID?)
                    }
                }
                .listStyle(.sidebar)
            }

            Divider()
            SidebarFooterView()
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        let collector = DropURLCollector()
        let group = DispatchGroup()

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    collector.append(url)
                } else if let url = item as? URL {
                    collector.append(url)
                }
            }
        }

        group.notify(queue: .main) {
            store.addPDFs(collector.urls)
        }
        return true
    }
}

private final class DropURLCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL] = []

    var urls: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ url: URL) {
        lock.lock()
        storage.append(url)
        lock.unlock()
    }
}
