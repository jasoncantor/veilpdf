import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: RedactionStore

    var body: some View {
        Form {
            Section("Detection") {
                Picker("Detector", selection: $store.settings.detectorMode) {
                    ForEach(DetectorMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                TextField("Model", text: $store.settings.modelIdentifier)

                HStack {
                    Text("Threshold")
                    Slider(value: $store.settings.threshold, in: 0.1...0.95, step: 0.05)
                    Text(store.settings.threshold.formatted(.number.precision(.fractionLength(2))))
                        .monospacedDigit()
                        .frame(width: 42, alignment: .trailing)
                }

                TextField("Python", text: $store.settings.pythonPath, prompt: Text("Auto-detect"))

                Toggle("Allow regex fallback", isOn: $store.settings.allowRegexFallback)
            }

            Section("PII Categories") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(store.settings.selectedLabelSummary)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Select All") {
                            store.settings.enableAllLabels()
                        }
                        Button("Reset") {
                            store.settings.resetLabels()
                        }
                    }

                    ForEach(RedactionSettings.labelGroups) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.title)
                                .font(.subheadline.weight(.semibold))
                            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                                let pairs = group.labels.chunked(into: 2)
                                ForEach(pairs.indices, id: \.self) { index in
                                    GridRow {
                                        ForEach(pairs[index]) { option in
                                            Toggle(option.title, isOn: labelBinding(option.id))
                                                .toggleStyle(.checkbox)
                                                .frame(minWidth: 180, alignment: .leading)
                                        }
                                        if pairs[index].count == 1 {
                                            Color.clear
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Section("Output") {
                HStack {
                    Text("Output")
                    Spacer()
                    Text(store.settings.outputFolder?.compactPath ?? "Next to source PDFs")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Button("Choose...") {
                        store.presentOutputFolderPanel()
                    }
                }
            }

            Section("Runtime") {
                HStack {
                    Button {
                        Task { await store.checkRuntime() }
                    } label: {
                        if store.isCheckingRuntime {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Check Runtime", systemImage: "stethoscope")
                        }
                    }

                    if let check = store.runtimeCheck {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(check.glinerAvailable ? "GLiNER available" : "GLiNER missing")
                                .foregroundStyle(check.glinerAvailable ? .green : .orange)
                            Text(check.python)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 620)
    }

    private func labelBinding(_ label: String) -> Binding<Bool> {
        Binding(
            get: {
                store.settings.labels.contains(label)
            },
            set: { isEnabled in
                store.settings.setLabel(label, isEnabled: isEnabled)
            }
        )
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [] }
        return stride(from: 0, to: count, by: size).map { start in
            Array(self[start..<Swift.min(start + size, count)])
        }
    }
}
