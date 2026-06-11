import SwiftUI

struct SidebarFooterView: View {
    @EnvironmentObject private var store: RedactionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: $store.settings.detectorMode) {
                ForEach(DetectorMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack {
                Button {
                    store.removeSelectedJob()
                } label: {
                    Label("Remove", systemImage: "minus")
                }
                .disabled(store.selectedJob == nil)

                Button {
                    store.clearFinished()
                } label: {
                    Label("Clear", systemImage: "checkmark")
                }
                .disabled(!store.jobs.contains { $0.status == .complete })

                Spacer()

                Button {
                    Task { await store.checkRuntime() }
                } label: {
                    Image(systemName: "stethoscope")
                }
                .help("Check GLiNER runtime")
            }
        }
        .padding(12)
    }
}
