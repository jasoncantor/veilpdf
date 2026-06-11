import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: RedactionStore

    private let labelColumns = [
        GridItem(.adaptive(minimum: 210), spacing: 12, alignment: .leading)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                settingsSection("Detection") {
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                        settingsRow("Detector") {
                            Picker("Detector", selection: $store.settings.detectorMode) {
                                ForEach(DetectorMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 220, alignment: .leading)
                        }

                        settingsRow("Model") {
                            TextField("Model", text: $store.settings.modelIdentifier)
                                .textFieldStyle(.roundedBorder)
                        }

                        settingsRow("Acceleration") {
                            Picker("Acceleration", selection: $store.settings.accelerationMode) {
                                ForEach(AccelerationMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 320, alignment: .leading)
                        }

                        settingsRow("Threshold") {
                            HStack(spacing: 12) {
                                Slider(value: $store.settings.threshold, in: 0.1...0.95, step: 0.05)
                                Text(store.settings.threshold.formatted(.number.precision(.fractionLength(2))))
                                    .monospacedDigit()
                                    .frame(width: 42, alignment: .trailing)
                            }
                        }

                        settingsRow("Python") {
                            TextField("Auto-detect", text: $store.settings.pythonPath)
                                .textFieldStyle(.roundedBorder)
                        }

                        settingsRow("Fallback") {
                            Toggle("Allow regex fallback", isOn: $store.settings.allowRegexFallback)
                                .toggleStyle(.switch)
                        }
                    }
                }

                settingsSection("PII Categories") {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 10) {
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
                            VStack(alignment: .leading, spacing: 8) {
                                Text(group.title)
                                    .font(.subheadline.weight(.semibold))

                                LazyVGrid(columns: labelColumns, alignment: .leading, spacing: 7) {
                                    ForEach(group.labels) { option in
                                        Toggle(option.title, isOn: labelBinding(option.id))
                                            .toggleStyle(.checkbox)
                                    }
                                }
                            }
                        }
                    }
                }

                settingsSection("Output") {
                    HStack(spacing: 12) {
                        Text("Output folder")
                            .foregroundStyle(.secondary)
                            .frame(width: 120, alignment: .leading)
                        Text(store.settings.outputFolder?.compactPath ?? "Next to source PDFs")
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        Spacer()
                        Button("Choose...") {
                            store.presentOutputFolderPanel()
                        }
                    }
                }

                settingsSection("Runtime") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            Button {
                                Task { await store.installRuntime() }
                            } label: {
                                if store.isInstallingRuntime {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Label("Install Included Runtime", systemImage: "square.and.arrow.down")
                                }
                            }
                            .disabled(store.isInstallingRuntime)

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
                            .disabled(store.isCheckingRuntime || store.isInstallingRuntime)
                        }

                        if !store.runtimeInstallMessage.isEmpty {
                            Text(store.runtimeInstallMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let check = store.runtimeCheck {
                            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
                                runtimeRow("Python", check.python)
                                runtimeRow("PyMuPDF", check.pymupdfAvailable ? "Available" : "Missing")
                                runtimeRow("GLiNER", check.glinerAvailable ? "Available" : "Missing")
                                if let modelAvailable = check.modelAvailable {
                                    runtimeRow("Model", modelAvailable ? "Ready" : "Not available")
                                }
                                if let device = check.device, !device.isEmpty {
                                    runtimeRow("Device", device)
                                }
                                if let modelCache = check.modelCache, !modelCache.isEmpty {
                                    runtimeRow("Cache", modelCache)
                                }
                            }
                        }
                    }
                }

                settingsSection("Updates") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Button {
                                Task { await store.checkForUpdates() }
                            } label: {
                                if store.isCheckingForUpdates {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Label("Check for Updates", systemImage: "arrow.triangle.2.circlepath")
                                }
                            }
                            .disabled(store.isCheckingForUpdates)

                            if store.updateInfo?.isUpdateAvailable == true {
                                Button("Download Update") {
                                    store.openAvailableUpdate()
                                }
                            }
                        }

                        if !store.updateMessage.isEmpty {
                            Text(store.updateMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 720, minHeight: 660)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.headline)
            content()
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private func settingsRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            content()
        }
    }

    @ViewBuilder
    private func runtimeRow(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
        }
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
