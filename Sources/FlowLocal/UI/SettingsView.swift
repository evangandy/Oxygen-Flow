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
        FlowPage(title: "Settings") {
            whisperSection
            cleanupSection
            toneSection
            systemSection
            privacySection
        }
        .frame(width: 560)
        .onAppear {
            accessibilityGranted = HotkeyManager.hasAccessibilityPermission
            loadModels()
        }
    }

    // MARK: - Speech-to-text

    private var whisperSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FlowSectionLabel(title: "Speech-to-text (Whisper)")
            FlowCard {
                LabeledContent("Model file") {
                    HStack {
                        TextField("Path to ggml .bin model", text: $settings.whisperModelPath)
                            .flowFieldStyle()
                            .frame(minWidth: 220)
                        Button("Choose…") { chooseWhisperModel() }
                            .buttonStyle(FlowProminentButtonStyle())
                    }
                }
                Text("The speech-to-text model — a whisper `ggml-*.bin` file. Highest quality is large-v3-turbo. Takes effect on next launch.")
                    .font(.caption).foregroundStyle(Palette.textSecondary)

                Divider().overlay(Palette.surfaceBorder)

                Picker("Language", selection: $settings.transcriptionLanguage) {
                    ForEach(AppSettings.languageOptions, id: \.code) { option in
                        Text(option.label).tag(option.code)
                    }
                }
                Text("Auto-detect adds a little latency but lets you switch languages between dictations. Pinning a language is fastest.")
                    .font(.caption).foregroundStyle(Palette.textSecondary)
            }
        }
    }

    // MARK: - Cleanup (Ollama)

    private var cleanupSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FlowSectionLabel(title: "Cleanup (Ollama)")
            FlowCard {
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

                Divider().overlay(Palette.surfaceBorder)

                Toggle("Adapt to active app (code editors, Gmail)", isOn: $settings.contextAwareFormatting)

                if settings.contextAwareFormatting {
                    ForEach(AppContext.allCases, id: \.self) { context in
                        Picker(context.label, selection: perContextStyleBinding(context)) {
                            Text("Default (\(settings.formattingStyle.rawValue))").tag(FormattingStyle?.none)
                            ForEach(FormattingStyle.allCases) { Text($0.rawValue).tag(FormattingStyle?.some($0)) }
                        }
                        .padding(.leading, 16)
                    }
                    Text("Per-app style — e.g. Very Casual for chat apps, Formal for email — overrides the Style above just for that context.")
                        .font(.caption).foregroundStyle(Palette.textSecondary)
                }

                Divider().overlay(Palette.surfaceBorder)

                Toggle("Voice commands (\u{201C}scratch that\u{201D}, \u{201C}new paragraph\u{201D})", isOn: $settings.voiceCommandsEnabled)

                Toggle("Auto-submit (press Return after pasting)", isOn: $settings.autoSubmitEnabled)
                Text("Off by default — this is global, so leave it off unless you're mainly dictating into chat-style boxes. It'll submit forms and add newlines everywhere else too.")
                    .font(.caption).foregroundStyle(Palette.textSecondary)

                Divider().overlay(Palette.surfaceBorder)

                LabeledContent("Ollama endpoint") {
                    TextField("", text: $settings.ollamaEndpoint)
                        .flowFieldStyle()
                }

                Text("Oxygen Flow lists the models installed in your local Ollama. Smaller models (e.g. qwen2.5:3b-instruct) are faster; larger ones format better. Nothing leaves your Mac.")
                    .font(.caption).foregroundStyle(Palette.textSecondary)
            }
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
                    .font(.caption).foregroundStyle(Palette.textSecondary)
            } else {
                Text("\(installedModels.count) model\(installedModels.count == 1 ? "" : "s") installed.")
                    .font(.caption).foregroundStyle(Palette.textSecondary)
            }
        case .loading:
            Text("Loading models…").font(.caption).foregroundStyle(Palette.textSecondary)
        case .failed(let msg):
            Text("Can't reach Ollama: \(msg). Is `ollama serve` running?")
                .font(.caption).foregroundStyle(Palette.danger)
        }
    }

    // MARK: - Tone

    private var toneSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FlowSectionLabel(title: "Personal tone")
            FlowCard {
                TextEditor(text: $settings.toneSampleText)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 80, maxHeight: 140)
                    .background(
                        RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                            .fill(Palette.windowBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                            .strokeBorder(Palette.surfaceBorder, lineWidth: 1)
                    )
                Text("Paste a few paragraphs you've written (emails, notes, docs) and cleanup/rewrite will try to match your voice — word choice and sentence rhythm — instead of a generic one. Leave blank to skip.")
                    .font(.caption).foregroundStyle(Palette.textSecondary)
            }
        }
    }

    // MARK: - System

    private var systemSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FlowSectionLabel(title: "System")
            FlowCard {
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
                    .font(.caption).foregroundStyle(Palette.textSecondary)

                Divider().overlay(Palette.surfaceBorder)

                LabeledContent("Rewrite selection shortcut") {
                    HStack(spacing: 8) {
                        ShortcutField(keyCode: $settings.rewriteHotkeyKeyCode,
                                      modifierFlags: $settings.rewriteHotkeyModifierFlags)
                        Button("Reset") {
                            settings.rewriteHotkeyKeyCode = AppSettings.defaultRewriteHotkeyKeyCode
                            settings.rewriteHotkeyModifierFlags = AppSettings.defaultRewriteHotkeyModifierFlags
                        }
                        .controlSize(.small)
                    }
                }
                Text("Select text in any app and press this to rewrite it in place with the local model, using the Style below. Default is Control+Command+R.")
                    .font(.caption).foregroundStyle(Palette.textSecondary)

                Divider().overlay(Palette.surfaceBorder)

                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                    .onChange(of: settings.launchAtLogin) { _, on in setLaunchAtLogin(on) }
                LabeledContent("Accessibility permission") {
                    HStack {
                        Image(systemName: accessibilityGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(accessibilityGranted ? Palette.textPrimary : Palette.danger)
                        if !accessibilityGranted {
                            Button("Grant…") { HotkeyManager.requestAccessibilityPermission() }
                                .buttonStyle(FlowProminentButtonStyle())
                        }
                    }
                }
            }
        }
    }

    // MARK: - Privacy / history

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FlowSectionLabel(title: "Privacy & history")
            FlowCard {
                Toggle("Save dictation history", isOn: $settings.saveHistoryEnabled)
                Text(settings.saveHistoryEnabled
                     ? "Every dictation is saved locally as plain-text JSON — both the raw transcript and the cleaned result — so you can review exactly what the model changed."
                     : "Privacy mode: dictations are delivered but never written to disk. Nothing to review in History afterward.")
                    .font(.caption).foregroundStyle(Palette.textSecondary)
                HStack {
                    Button("Reveal history in Finder") { revealHistory() }
                        .buttonStyle(FlowProminentButtonStyle())
                    Spacer()
                    Button("Clear history…") { confirmClear() }
                        .buttonStyle(.plain)
                        .foregroundStyle(Palette.danger)
                }
            }
        }
    }

    // MARK: - Actions

    private func perContextStyleBinding(_ context: AppContext) -> Binding<FormattingStyle?> {
        Binding(
            get: { settings.perContextStyle[context.rawValue].flatMap(FormattingStyle.init(rawValue:)) },
            set: { settings.setStyle($0, for: context) }
        )
    }

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
