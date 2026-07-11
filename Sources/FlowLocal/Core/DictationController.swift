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
        case error(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var level: Float = 0
    /// Whether the model/warm-up finished; the menu bar reflects readiness.
    @Published private(set) var isReady = false
    @Published private(set) var lastError: String?

    private let settings = AppSettings.shared
    private let hotkey = HotkeyManager()
    private let recorder = AudioRecorder()
    // Accessed on `inferenceQueue` (serialized), never concurrently with the main actor.
    private nonisolated(unsafe) let transcriber = Transcriber()
    private let cleanup = Cleanup()
    private let injector = TextInjector()

    /// The app the user was dictating into, captured when recording stops.
    private var targetAppName: String?
    private var targetContext: AppContext = .general
    private var copiedResetTask: Task<Void, Never>?

    private var cancellables = Set<AnyCancellable>()
    private var accessibilityTimer: Timer?
    private let inferenceQueue = DispatchQueue(label: "flowlocal.inference", qos: .userInitiated)

    init() {
        recorder.$level
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.level = $0 }
            .store(in: &cancellables)

        hotkey.onToggle = { [weak self] in self?.toggle() }

        // Keep the global hotkey in sync with the user's configured shortcut.
        hotkey.configure(keyCode: settings.hotkeyKeyCode, modifierFlags: settings.hotkeyModifierFlags)
        Publishers.CombineLatest(settings.$hotkeyKeyCode, settings.$hotkeyModifierFlags)
            .receive(on: RunLoop.main)
            .sink { [weak self] code, flags in self?.hotkey.configure(keyCode: code, modifierFlags: flags) }
            .store(in: &cancellables)
    }

    // MARK: - Lifecycle

    /// Called once at launch: request permissions, start the hotkey, warm the models.
    func bootstrap() {
        NSLog("[Cobalt] bootstrap() starting")
        NSLog("[Cobalt] AXIsProcessTrusted = \(HotkeyManager.hasAccessibilityPermission)")

        AudioRecorder.requestMicrophonePermission { granted in
            NSLog("[Cobalt] Microphone permission: \(granted)")
        }

        if !HotkeyManager.hasAccessibilityPermission {
            NSLog("[Cobalt] Accessibility NOT granted — requesting prompt")
            HotkeyManager.requestAccessibilityPermission()
        }

        let tapOk = hotkey.start()
        NSLog("[Cobalt] hotkey.start() = \(tapOk)")
        if !tapOk {
            lastError = "Grant Accessibility permission, then relaunch."
        }

        // Periodically retry the event tap in case the user grants permission after launch.
        startAccessibilityRetryTimer()

        cleanup.warmUp(endpoint: settings.ollamaEndpoint, model: settings.ollamaModel)

        // Load whisper off the main thread; mark ready when done.
        let path = settings.whisperModelPath
        NSLog("[Cobalt] Loading whisper model from: \(path)")
        inferenceQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.transcriber.loadModel(at: path)
                NSLog("[Cobalt] Whisper model loaded OK")
                Task { @MainActor in self.isReady = true }
            } catch {
                NSLog("[Cobalt] Whisper model FAILED: \(error)")
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
                let trusted = HotkeyManager.hasAccessibilityPermission
                if trusted {
                    let ok = self.hotkey.start()
                    if ok {
                        NSLog("[Cobalt] ✅ Event tap connected successfully!")
                        self.lastError = nil
                        timer.invalidate()
                        self.accessibilityTimer = nil
                    } else {
                        NSLog("[Cobalt] AX trusted but tap failed — will retry")
                    }
                }
            }
        }
    }

    /// Re-check the hotkey tap after the user grants Accessibility (from the menu).
    func retryHotkey() {
        NSLog("[Cobalt] retryHotkey() — AX trusted: \(HotkeyManager.hasAccessibilityPermission)")
        if hotkey.start() {
            NSLog("[Cobalt] ✅ retryHotkey succeeded")
            lastError = nil
        } else {
            NSLog("[Cobalt] ❌ retryHotkey failed")
        }
    }

    // MARK: - Toggle / cancel

    func toggle() {
        NSLog("[Cobalt] toggle() — current state: \(state)")
        switch state {
        case .idle, .error, .copied:
            startListening()
        case .listening:
            stopAndProcess()
        case .transcribing, .cleaning:
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
            if HotkeyManager.hasAccessibilityPermission {
                lastError = nil
            } else {
                lastError = "Grant Accessibility permission, then relaunch."
            }
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
        Task {
            do {
                let raw = try await transcribeAsync(samples)
                NSLog("[Cobalt] Transcription: '\(raw)'")
                guard !raw.isEmpty else { state = .idle; return }

                let audioDuration = Double(samples.count) / 16_000.0
                // Give focus a beat to settle back on the target field after hiding.
                let editable = TextInjector.focusedElementIsEditable()

                var finalText = raw
                if settings.cleanupEnabled {
                    state = .cleaning
                    finalText = await produceCleaned(raw: raw, streamToCursor: editable)
                } else if editable {
                    injector.injectAtCursor(raw)
                }

                let delivery: DeliveryMode
                if editable {
                    delivery = .pasted
                    state = .idle
                } else {
                    injector.copyToClipboard(finalText)
                    delivery = .copied
                    state = .copied
                    scheduleCopiedReset()
                }

                TranscriptionStore.shared.add(
                    raw: raw, cleaned: finalText, audioDuration: audioDuration,
                    appName: appName, delivery: delivery
                )
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
    private func produceCleaned(raw: String, streamToCursor: Bool) async -> String {
        let session = streamToCursor ? injector.makeSession() : nil
        do {
            let full = try await cleanup.clean(
                raw: raw,
                endpoint: settings.ollamaEndpoint,
                model: settings.ollamaModel,
                style: settings.formattingStyle,
                context: targetContext,
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

    private func transcribeAsync(_ samples: [Float]) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            inferenceQueue.async { [weak self] in
                guard let self else { cont.resume(returning: ""); return }
                do {
                    let text = try self.transcriber.transcribe(samples: samples)
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
}
