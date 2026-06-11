import SwiftUI

struct StatusBarView: View {
    @EnvironmentObject private var store: RedactionStore

    var body: some View {
        HStack(spacing: 10) {
            if store.isRedacting {
                ProgressView()
                    .controlSize(.small)
            }
            Text(store.bannerMessage)
                .lineLimit(1)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(store.jobs.count) job\(store.jobs.count == 1 ? "" : "s")")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
