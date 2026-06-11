import SwiftUI

struct JobRowView: View {
    let job: RedactionJob

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(job.inputURL.lastPathComponent)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }

    private var subtitle: String {
        switch job.status {
        case .complete:
            "\(job.redactionCount) redaction\(job.redactionCount == 1 ? "" : "s")"
        case .failed:
            "Failed"
        case .running:
            "Running"
        case .queued:
            "Queued"
        }
    }

    private var icon: String {
        switch job.status {
        case .queued:
            "doc"
        case .running:
            "gearshape"
        case .complete:
            "checkmark.circle"
        case .failed:
            "exclamationmark.triangle"
        }
    }

    private var color: Color {
        switch job.status {
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
