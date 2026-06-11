import SwiftUI

struct DetailView: View {
    let job: RedactionJob?

    var body: some View {
        Group {
            if let job {
                VStack(alignment: .leading, spacing: 24) {
                    header(job)

                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 18, verticalSpacing: 12) {
                        infoRow("Input", job.inputURL.compactPath)
                        infoRow("Output", job.outputURL.compactPath)
                        infoRow("Status", job.status.title)
                        infoRow("Detector", job.detector.isEmpty ? "-" : job.detector)
                        infoRow("Redactions", "\(job.redactionCount)")
                        infoRow("Message", job.message)
                    }
                    .textSelection(.enabled)

                    Spacer()
                }
                .padding(28)
            } else {
                ContentUnavailableView(
                    "No PDF Selected",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Add a PDF to start a redaction job.")
                )
            }
        }
    }

    private func header(_ job: RedactionJob) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: statusIcon(for: job.status))
                .font(.system(size: 28))
                .foregroundStyle(statusColor(for: job.status))
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(job.inputURL.lastPathComponent)
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(job.outputURL.lastPathComponent)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .lineLimit(nil)
        }
    }

    private func statusIcon(for status: RedactionStatus) -> String {
        switch status {
        case .queued:
            "clock"
        case .running:
            "gearshape.2"
        case .complete:
            "checkmark.seal"
        case .failed:
            "exclamationmark.triangle"
        }
    }

    private func statusColor(for status: RedactionStatus) -> Color {
        switch status {
        case .queued:
            .secondary
        case .running:
            .blue
        case .complete:
            .green
        case .failed:
            .red
        }
    }
}
