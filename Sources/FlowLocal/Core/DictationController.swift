import AppKit
import Combine
import Foundation

/// The dictation state machine. Owns all subsystems and orchestrates
/// hotkey -> record -> transcribe -> cleanup -> deliver. Published state drives the pill overlay.
@MainActor
final class DictationController: ObservableObject {

    enum State: Equatable {
        case idle
        case listening
        case transcribing
        case cleaning
        case copied         // finished, text placed on the clipboard (no editable field was focused)
        case rewriting      // "rewrite selection" command: reading the selection + calling the model
        case rewritten      // rewrite finished and pasted back; brief confirmation before idle
        case error(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var level: Float = 0
    /// Whether the model/warm-up finished; the menu bar reflects readiness.
    @Published private(set) var isReady = false
    @Published private(set) var lastError: String?

    private static let accessibilityNeeded = "Grant Accessibility permission, then relaunch."

    private let settings = AppSettings.shared
    private let hotkey = HotkeyManager()
    private let rewriteHotkey = HotkeyManager()
    private let recorder = AudioRecorder()
    // Accessed on `inferenceQueue` (serialized), never concurrently with the main actor.
    private nonisolated(unsafe) let transcriber = Transcriber()
    private let cleanup = Cleanup()
    private let injector = TextInjector()

    /// The app the user was dictating into, captured when recording stops.
    private var targetAppName: String?
    private var targetContext: AppContext = .general
    private var copiedResetTask: Task<Void, Never>?
    private var rewrittenResetTask: Task<Void, Never>?

    private var cancellables = Set<AnyCancellable>()
    private var accessibilityTimer: Timer?
    private let inferenceQueue = DispatchQueue(label: "flowlocal.inference", qos: .userInitiated)

    init() {
        recorder.$level
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.level = $0 }
            .store(in: &cancellables)

        hotkey.onToggle = { [weak self] in self?.toggle() }
        rewriteHotkey.onToggle = { [weak self] in self?.triggerRewrite() }

        // Keep the global hotkey in sync with the user's configured shortcut.
        hotkey.configure(keyCode: settings.hotkeyKeyCode, modifierFlags: settings.hotkeyModifierFlags)
        Publishers.CombineLatest(settings.$hotkeyKeyCode, settings.$hotkeyModifierFlags)
            .receive(on: RunLoop.main)
            .sink { [weak self] code, flags in self?.hotkey.configure(keyCode: code, modifierFlags: flags) }
            .store(in: &cancellables)

        rewriteHotkey.configure(keyCode: settings.rewriteHotkeyKeyCode, modifierFlags: settings.rewriteHotkeyModifierFlags)
        Publishers.CombineLatest(settings.$rewriteHotkeyKeyCode, settings.$rewriteHotkeyModifierFlags)
            .receive(on: RunLoop.main)
            .sink { [weak self] code, flags in self?.rewriteHotkey.configure(keyCode: code, modifierFlags: flags) }
            .store(in: &cancellables)
    }

    // MARK: - Lifecycle

    /// Called once at launch: request permissions, start the hotkey, warm the models.
    func bootstrap() {
        AudioRecorder.requestMicrophonePermission { _ in }

        if !HotkeyManager.hasAccessibilityPermission {
            HotkeyManager.requestAccessibilityPermission()
        }

        if !hotkey.start() {
            lastError = Self.accessibilityNeeded
        }
        rewriteHotkey.start()

        // Periodically retry the event tap in case the user grants permission after launch.
        startAccessibilityRetryTimer()

        // Make sure Ollama is up (start it if needed), then warm the model. Warm again shortly
        // after in case we just launched the server and it wasn't ready on the first try.
        OllamaLauncher.ensureRunning(endpoint: settings.ollamaEndpoint)
        cleanup.warmUp(endpoint: settings.ollamaEndpoint, model: settings.ollamaModel)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self else { return }
            self.cleanup.warmUp(endpoint: self.settings.ollamaEndpoint, model: self.settings.ollamaModel)
        }

        // Load whisper off the main thread; mark ready when done.
        let path = settings.whisperModelPath
        inferenceQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.transcriber.loadModel(at: path)
                Task { @MainActor in self.isReady = true }
            } catch {
                NSLog("[Cobalt] Whisper model failed to load: \(error)")
                Task { @MainActor in
                    self.lastError = error.localizedDescription
                    self.state = .error(error.localizedDescription)
                }
            }
        }
    }

    /// Retry connecting the event tap every 2 seconds until it succeeds.
    private func startAccessibilityRetryTimer() {
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            Task { @MainActor in
                guard HotkeyManager.hasAccessibilityPermission, self.hotkey.start() else { return }
                self.rewriteHotkey.start()
                self.lastError = nil
                timer.invalidate()
                self.accessibilityTimer = nil
            }
        }
    }

    /// Re-check the hotkey tap after the user grants Accessibility (from the menu).
    func retryHotkey() {
        if hotkey.start() { lastError = nil }
        rewriteHotkey.start()
    }

    // MARK: - Toggle / cancel

    func toggle() {
        switch state {
        case .idle, .error, .copied, .rewritten:
            startListening()
        case .listening:
            stopAndProcess()
        case .transcribing, .cleaning, .rewriting:
            break // busy; ignore
        }
    }

    /// Discard the current recording without transcribing (the chip's ✕ button).
    func cancel() {
        guard state == .listening else { return }
        _ = recorder.stop()
        state = .idle
        if NSApp.isActive { NSApp.hide(nil) }
    }

    private func startListening() {
        copiedResetTask?.cancel()
        do {
            try recorder.start()
            lastError = HotkeyManager.hasAccessibilityPermission ? nil : Self.accessibilityNeeded
            state = .listening
        } catch {
            state = .error(error.localizedDescription)
            flashErrorThenIdle()
        }
    }

    private func stopAndProcess() {
        // Remember which app to deliver into (and its formatting context) before we hide.
        if let front = NSWorkspace.shared.frontmostApplication?.localizedName,
           front != "Oxygen Flow" {
            targetAppName = front
        }
        targetContext = settings.contextAwareFormatting ? AppContext.detect() : .general

        let samples = recorder.stop()
        state = .transcribing

        // Hide the UI so focus returns to the previous text field for pasting.
        if NSApp.isActive {
            NSApp.hide(nil)
        }

        runPipeline(samples: samples)
    }

    // MARK: - Pipeline

    private func runPipeline(samples: [Float]) {
        let appName = targetAppName
        let vocabulary = DictionaryStore.shared.whisperVocabulary
        let language = settings.whisperLanguageCode
        let glossary = DictionaryStore.shared.cleanupGlossary
        Task {
            do {
                let raw = try await transcribeAsync(samples, language: language, vocabulary: vocabulary)
                guard !raw.isEmpty else { state = .idle; return }

                // In-line commands ("scratch that", "new paragraph") act on the raw transcript
                // before anything else sees it.
                let commanded = settings.voiceCommandsEnabled ? VoiceCommands.process(raw) : raw
                guard !commanded.isEmpty else { state = .idle; return }

                let audioDuration = Double(samples.count) / 16_000.0
                // Give focus a beat to settle back on the target field after hiding.
                let editable = TextInjector.focusedElementIsEditable()

                var finalText = commanded
                if let snippet = SnippetStore.shared.match(commanded) {
                    // Whole utterance matched a voice macro — deliver the canned expansion
                    // verbatim, skipping cleanup entirely.
                    finalText = snippet
                    if editable { injector.injectAtCursor(finalText) }
                } else if settings.cleanupEnabled {
                    state = .cleaning
                    finalText = await produceCleaned(raw: commanded, streamToCursor: editable, glossary: glossary)
                } else if editable {
                    injector.injectAtCursor(commanded)
                }

                let delivery: DeliveryMode
                if editable {
                    delivery = .pasted
                    if settings.autoSubmitEnabled { injector.pressReturn() }
                    state = .idle
                } else {
                    injector.copyToClipboard(finalText)
                    delivery = .copied
                    state = .copied
                    scheduleCopiedReset()
                }

                if settings.saveHistoryEnabled {
                    TranscriptionStore.shared.add(
                        raw: raw, cleaned: finalText, audioDuration: audioDuration,
                        appName: appName, delivery: delivery
                    )
                }
            } catch {
                state = .error(error.localizedDescription)
                lastError = error.localizedDescription
                flashErrorThenIdle()
            }
        }
    }

    /// Run Ollama cleanup, returning the full cleaned text. When `streamToCursor` is true the
    /// text is progressively pasted at the cursor as it generates; otherwise it is only collected
    /// (for the copy-to-clipboard path). Falls back to the raw transcript if Ollama fails.
    private func produceCleaned(raw: String, streamToCursor: Bool, glossary: String?) async -> String {
        let session = streamToCursor ? injector.makeSession() : nil
        do {
            let full = try await cleanup.clean(
                raw: raw,
                endpoint: settings.ollamaEndpoint,
                model: settings.ollamaModel,
                style: settings.style(for: targetContext),
                context: targetContext,
                glossary: glossary,
                tone: settings.toneGuidance,
                onDelta: { session?.feed($0) }
            )
            session?.finish()
            return full.isEmpty ? raw : full
        } catch {
            NSLog("[Cobalt] Cleanup failed, falling back to raw: \(error.localizedDescription)")
            if let session {
                if session.pastedAny { session.finish() } else { injector.injectAtCursor(raw) }
            }
            return raw
        }
    }

    private func scheduleCopiedReset() {
        copiedResetTask?.cancel()
        copiedResetTask = Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if state == .copied { state = .idle }
        }
    }

    private func transcribeAsync(_ samples: [Float], language: String?, vocabulary: String) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            inferenceQueue.async { [weak self] in
                guard let self else { cont.resume(returning: ""); return }
                do {
                    let text = try self.transcriber.transcribe(samples: samples, language: language, vocabulary: vocabulary)
                    cont.resume(returning: text)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    private func flashErrorThenIdle() {
        Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            if case .error = state { state = .idle }
        }
    }

    // MARK: - Rewrite selection ("click text, rephrase")

    /// Fired by the rewrite hotkey: capture whatever is selected in the frontmost app, send it to
    /// the local model for a real rewrite (not the minimal dictation cleanup), and paste the
    /// result back over the selection.
    func triggerRewrite() {
        guard state == .idle || state == .copied || state == .rewritten else { return }
        rewrittenResetTask?.cancel()
        Task { await performRewrite() }
    }

    private func performRewrite() async {
        state = .rewriting
        // Detect context before captureSelection's Cmd+C briefly steals focus/settles the pasteboard.
        let context = settings.contextAwareFormatting ? AppContext.detect() : .general
        guard let capture = TextInjector.captureSelection() else {
            state = .error("No text selected")
            flashErrorThenIdle()
            return
        }
        do {
            let rewritten = try await cleanup.rewrite(
                text: capture.text,
                endpoint: settings.ollamaEndpoint,
                model: settings.ollamaModel,
                style: settings.style(for: context),
                glossary: DictionaryStore.shared.cleanupGlossary,
                tone: settings.toneGuidance
            )
            guard !rewritten.isEmpty else {
                injector.replaceSelection(with: capture.text, originalClipboard: capture.originalClipboard)
                state = .idle
                return
            }
            injector.replaceSelection(with: rewritten, originalClipboard: capture.originalClipboard)
            state = .rewritten
            scheduleRewrittenReset()
        } catch {
            // Put the original selection back so nothing is lost on failure.
            injector.replaceSelection(with: capture.text, originalClipboard: capture.originalClipboard)
            state = .error(error.localizedDescription)
            lastError = error.localizedDescription
            flashErrorThenIdle()
        }
    }

    private func scheduleRewrittenReset() {
        rewrittenResetTask?.cancel()
        rewrittenResetTask = Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            if state == .rewritten { state = .idle }
        }
    }
}
