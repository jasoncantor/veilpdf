import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: RedactionStore

    var body: some View {
        Form {
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

            Divider()

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
        .formStyle(.grouped)
        .padding()
    }
}
