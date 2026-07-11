import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @State private var accessibilityGranted = HotkeyManager.hasAccessibilityPermission

    var body: some View {
        Form {
            Section("Speech-to-text (Whisper)") {
                LabeledContent("Model file") {
                    HStack {
                        TextField("Path to ggml model", text: $settings.whisperModelPath)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 260)
                        Button("Choose…") { chooseModel() }
                    }
                }
                Text("Highest quality: large-v3-turbo. Changing this takes effect on next launch.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Cleanup (Ollama)") {
                Toggle("Clean up grammar & formatting", isOn: $settings.cleanupEnabled)
                Picker("Style", selection: $settings.formattingStyle) {
                    ForEach(FormattingStyle.allCases) { Text($0.rawValue).tag($0) }
                }
                TextField("Ollama endpoint", text: $settings.ollamaEndpoint)
                    .textFieldStyle(.roundedBorder)
                TextField("Model", text: $settings.ollamaModel)
                    .textFieldStyle(.roundedBorder)
                Text("Default qwen2.5:3b-instruct (fast). Use qwen2.5:7b-instruct for higher quality.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("System") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                    .onChange(of: settings.launchAtLogin) { _, on in setLaunchAtLogin(on) }
                LabeledContent("Accessibility permission") {
                    HStack {
                        Image(systemName: accessibilityGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(accessibilityGranted ? .green : .red)
                        if !accessibilityGranted {
                            Button("Grant…") {
                                HotkeyManager.requestAccessibilityPermission()
                            }
                        }
                    }
                }
                Text("Hotkey: Control+~ (press to start, press again to stop).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .padding()
        .onAppear { accessibilityGranted = HotkeyManager.hasAccessibilityPermission }
    }

    private func chooseModel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = []
        panel.allowsOtherFileTypes = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            settings.whisperModelPath = url.path
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Launch-at-login toggle failed: \(error.localizedDescription)")
        }
    }
}
