import AppKit
import SwiftUI

@main
struct VeilPDFApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = RedactionStore()

    var body: some Scene {
        WindowGroup("VeilPDF") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 980, minHeight: 620)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    Task { await store.checkForUpdates(openIfAvailable: true) }
                }
                .disabled(store.isCheckingForUpdates)
            }

            CommandGroup(after: .newItem) {
                Button("Add PDFs...") {
                    store.presentImportPanel()
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("Redact Pending") {
                    Task { await store.redactPending() }
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(!store.canRedact)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(store)
                .frame(minWidth: 720, minHeight: 660)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
