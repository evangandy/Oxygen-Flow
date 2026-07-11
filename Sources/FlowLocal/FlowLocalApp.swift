import AppKit
import SwiftUI

struct FlowLocalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup(id: "main") {
            MainWindowView(controller: delegate.controller)
        }

        MenuBarExtra {
            MenuContent(controller: delegate.controller)
        } label: {
            Image(systemName: delegate.controller.state == .idle ? "waveform" : "waveform.circle.fill")
        }

        Settings {
            SettingsView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = DictationController()
    private var pill: PillWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Regular app with Dock icon and main window
        NSApp.setActivationPolicy(.regular)
        pill = PillWindowController(controller: controller)
        controller.bootstrap()
    }
}

/// The menu-bar dropdown.
struct MenuContent: View {
    @ObservedObject var controller: DictationController
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Dashboard") { openWindow(id: "main") }
        
        Button(controller.state == .listening ? "Stop Dictation" : "Start Dictation") {
            controller.toggle()
        }
        .keyboardShortcut("`", modifiers: [.control])

        Divider()

        Text(statusText)

        if let err = controller.lastError {
            Text("⚠︎ \(err)").foregroundStyle(.secondary)
            Button("Grant Accessibility & Retry") {
                HotkeyManager.requestAccessibilityPermission()
                controller.retryHotkey()
            }
        }

        Divider()

        Button("Settings…") { openSettings() }
            .keyboardShortcut(",", modifiers: .command)
        Button("Quit Cobalt Flow") { NSApp.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }

    private var statusText: String {
        switch controller.state {
        case .idle:
            return controller.isReady ? "Ready — \(AppSettings.shared.hotkeyDisplayString) to dictate" : "Loading model…"
        case .listening: return "Listening…"
        case .transcribing: return "Transcribing…"
        case .cleaning: return "Formatting…"
        case .copied: return "Copied to clipboard"
        case .error(let m): return "Error: \(m)"
        }
    }
}
