import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @State private var accessibilityGranted = HotkeyManager.hasAccessibilityPermission

    // Ollama model discovery
    @State private var installedModels: [String] = []
    @State private var modelLoadState: ModelLoadState = .idle
    private let cleanup = Cleanup()

    enum ModelLoadState: Equatable { case idle, loading, loaded, failed(String) }

    var body: some View {
        Form {
            whisperSection
            cleanupSection
            systemSection
            privacySection
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .onAppear {
            accessibilityGranted = HotkeyManager.hasAccessibilityPermission
            loadModels()
        }
    }

    // MARK: - Speech-to-text

    private var whisperSection: some View {
        Section {
            LabeledContent("Model file") {
                HStack {
                    TextField("Path to ggml .bin model", text: $settings.whisperModelPath)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 240)
                    Button("Choose…") { chooseWhisperModel() }
                }
            }
            Text("The speech-to-text model — a whisper `ggml-*.bin` file. Highest quality is large-v3-turbo. Takes effect on next launch.")
                .font(.caption).foregroundStyle(.secondary)
        } header: {
            Text("Speech-to-text (Whisper)")
        }
    }

    // MARK: - Cleanup (Ollama)

    private var cleanupSection: some View {
        Section {
            Toggle("Clean up grammar & formatting", isOn: $settings.cleanupEnabled)

            LabeledContent("AI model") {
                HStack(spacing: 8) {
                    modelPicker
                    Button {
                        loadModels()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Reload installed Ollama models")
                }
            }

            modelStatusText

            Picker("Style", selection: $settings.formattingStyle) {
                ForEach(FormattingStyle.allCases) { Text($0.rawValue).tag($0) }
            }

            Toggle("Adapt to active app (code editors, Gmail)", isOn: $settings.contextAwareFormatting)

            TextField("Ollama endpoint", text: $settings.ollamaEndpoint)
                .textFieldStyle(.roundedBorder)
        } header: {
            Text("Cleanup (Ollama)")
        } footer: {
            Text("Oxygen Flow lists the models installed in your local Ollama. Smaller models (e.g. qwen2.5:3b-instruct) are faster; larger ones format better. Nothing leaves your Mac.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var modelPicker: some View {
        // Include the current selection even if Ollama isn't reachable, so it never disappears.
        let options = (installedModels + [settings.ollamaModel])
            .reduce(into: [String]()) { acc, m in if !acc.contains(m) { acc.append(m) } }

        Picker("", selection: $settings.ollamaModel) {
            ForEach(options, id: \.self) { Text($0).tag($0) }
        }
        .labelsHidden()
        .frame(minWidth: 220)
        .onChange(of: settings.ollamaModel) { _, newModel in
            // Warm the newly selected model so the next dictation is instant.
            cleanup.warmUp(endpoint: settings.ollamaEndpoint, model: newModel)
        }
    }

    @ViewBuilder private var modelStatusText: some View {
        switch modelLoadState {
        case .idle, .loaded:
            if installedModels.isEmpty {
                Text("No models found. Pull one with `ollama pull qwen2.5:3b-instruct`.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("\(installedModels.count) model\(installedModels.count == 1 ? "" : "s") installed.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .loading:
            Text("Loading models…").font(.caption).foregroundStyle(.secondary)
        case .failed(let msg):
            Text("Can't reach Ollama: \(msg). Is `ollama serve` running?")
                .font(.caption).foregroundStyle(.orange)
        }
    }

    // MARK: - System

    private var systemSection: some View {
        Section("System") {
            LabeledContent("Dictation shortcut") {
                HStack(spacing: 8) {
                    ShortcutField(keyCode: $settings.hotkeyKeyCode,
                                  modifierFlags: $settings.hotkeyModifierFlags)
                    Button("Reset") {
                        settings.hotkeyKeyCode = AppSettings.defaultHotkeyKeyCode
                        settings.hotkeyModifierFlags = AppSettings.defaultHotkeyModifierFlags
                    }
                    .controlSize(.small)
                }
            }
            Text("Press to start dictating, press again to stop. Default is Control+~. Click the shortcut to record your own (e.g. ⌥Space).")
                .font(.caption).foregroundStyle(.secondary)

            Toggle("Launch at login", isOn: $settings.launchAtLogin)
                .onChange(of: settings.launchAtLogin) { _, on in setLaunchAtLogin(on) }
            LabeledContent("Accessibility permission") {
                HStack {
                    Image(systemName: accessibilityGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(accessibilityGranted ? .green : .red)
                    if !accessibilityGranted {
                        Button("Grant…") { HotkeyManager.requestAccessibilityPermission() }
                    }
                }
            }
        }
    }

    // MARK: - Privacy / history

    private var privacySection: some View {
        Section("Privacy & history") {
            Text("Every dictation is saved locally as plain-text JSON — both the raw transcript and the cleaned result — so you can review exactly what the model changed.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Reveal history in Finder") { revealHistory() }
                Spacer()
                Button("Clear history…", role: .destructive) { confirmClear() }
            }
        }
    }

    // MARK: - Actions

    private func loadModels() {
        modelLoadState = .loading
        let endpoint = settings.ollamaEndpoint
        Task {
            do {
                let models = try await cleanup.listModels(endpoint: endpoint)
                await MainActor.run {
                    installedModels = models
                    modelLoadState = .loaded
                }
            } catch {
                await MainActor.run {
                    modelLoadState = .failed(error.localizedDescription)
                }
            }
        }
    }

    private func chooseWhisperModel() {
        let panel = NSOpenPanel()
        panel.allowsOtherFileTypes = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.message = "Choose a whisper ggml model (.bin)"
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

    private func revealHistory() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("FlowLocal/history", isDirectory: true)
        NSWorkspace.shared.activateFileViewerSelecting([dir])
    }

    private func confirmClear() {
        let alert = NSAlert()
        alert.messageText = "Clear all dictation history?"
        alert.informativeText = "This permanently deletes every saved transcript. This can't be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            TranscriptionStore.shared.clearAll()
        }
    }
}
