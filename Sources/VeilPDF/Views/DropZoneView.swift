import SwiftUI

struct DropZoneView: View {
    let isTargeted: Bool

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 42))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
            Text("Drop PDFs Here")
                .font(.title3)
                .fontWeight(.semibold)
            Text("or use the Add PDFs button")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isTargeted ? Color.accentColor.opacity(0.12) : Color.clear)
    }
}
