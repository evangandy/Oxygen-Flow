import AppKit
import Combine
import Foundation

/// The dictation state machine. Owns all subsystems and orchestrates
/// hotkey -> record -> transcribe -> cleanup -> inject. Published state drives the pill overlay.
@MainActor
final class DictationController: ObservableObject {

    enum State: Equatable {
        case idle
        case listening
        case transcribing
        case cleaning
        case error(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var level: Float = 0
    @Published private(set) var partialTranscript: String = ""
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
    
    private var inferenceLoopTask: Task<Void, Never>?

    private var cancellables = Set<AnyCancellable>()
    private var accessibilityTimer: Timer?
    private let inferenceQueue = DispatchQueue(label: "flowlocal.inference", qos: .userInitiated)

    init() {
        recorder.$level
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.level = $0 }
            .store(in: &cancellables)

        hotkey.onToggle = { [weak self] in self?.toggle() }
    }

    // MARK: - Lifecycle

    /// Called once at launch: request permissions, start the hotkey, warm the models.
    func bootstrap() {
        NSLog("[FlowLocal] bootstrap() starting")
        NSLog("[FlowLocal] AXIsProcessTrusted = \(HotkeyManager.hasAccessibilityPermission)")
        
        AudioRecorder.requestMicrophonePermission { granted in
            NSLog("[FlowLocal] Microphone permission: \(granted)")
        }

        if !HotkeyManager.hasAccessibilityPermission {
            NSLog("[FlowLocal] Accessibility NOT granted — requesting prompt")
            HotkeyManager.requestAccessibilityPermission()
        }
        
        let tapOk = hotkey.start()
        NSLog("[FlowLocal] hotkey.start() = \(tapOk)")
        if !tapOk {
            lastError = "Grant Accessibility permission, then relaunch."
        }
        
        // Periodically retry the event tap in case the user grants permission after launch.
        startAccessibilityRetryTimer()

        cleanup.warmUp(endpoint: settings.ollamaEndpoint, model: settings.ollamaModel)

        // Load whisper off the main thread; mark ready when done.
        let path = settings.whisperModelPath
        NSLog("[FlowLocal] Loading whisper model from: \(path)")
        inferenceQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.transcriber.loadModel(at: path)
                NSLog("[FlowLocal] Whisper model loaded OK")
                Task { @MainActor in self.isReady = true }
            } catch {
                NSLog("[FlowLocal] Whisper model FAILED: \(error)")
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
                        NSLog("[FlowLocal] ✅ Event tap connected successfully!")
                        self.lastError = nil
                        timer.invalidate()
                        self.accessibilityTimer = nil
                    } else {
                        NSLog("[FlowLocal] AX trusted but tap failed — will retry")
                    }
                }
            }
        }
    }

    /// Re-check the hotkey tap after the user grants Accessibility (from the menu).
    func retryHotkey() {
        NSLog("[FlowLocal] retryHotkey() — AX trusted: \(HotkeyManager.hasAccessibilityPermission)")
        // Toggle the accessibility list: remove and re-add to force macOS to re-evaluate
        if hotkey.start() {
            NSLog("[FlowLocal] ✅ retryHotkey succeeded")
            lastError = nil
        } else {
            NSLog("[FlowLocal] ❌ retryHotkey failed")
        }
    }

    // MARK: - Toggle

    func toggle() {
        NSLog("[FlowLocal] toggle() — current state: \(state)")
        switch state {
        case .idle, .error:
            startListening()
        case .listening:
            stopAndProcess()
        case .transcribing, .cleaning:
            break // busy; ignore
        }
    }

    private func startListening() {
        do {
            try recorder.start()
            if HotkeyManager.hasAccessibilityPermission {
                lastError = nil
            } else {
                lastError = "Grant Accessibility permission, then relaunch."
            }
            partialTranscript = ""
            state = .listening
            
            inferenceLoopTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    guard !Task.isCancelled, state == .listening else { break }
                    let current = recorder.currentSamples()
                    guard current.count > 8000 else { continue }
                    if let partial = try? await transcribeAsync(current) {
                        await MainActor.run {
                            if self.state == .listening {
                                self.partialTranscript = partial
                            }
                        }
                    }
                }
            }
        } catch {
            state = .error(error.localizedDescription)
            flashErrorThenIdle()
        }
    }

    private func stopAndProcess() {
        inferenceLoopTask?.cancel()
        inferenceLoopTask = nil
        
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
        Task {
            do {
                let raw = try await transcribeAsync(samples)
                NSLog("[FlowLocal] Transcription result: '\(raw)'")
                guard !raw.isEmpty else { NSLog("[FlowLocal] Empty transcription, returning to idle"); state = .idle; return }

                if settings.cleanupEnabled {
                    state = .cleaning
                    NSLog("[FlowLocal] Starting cleanup…")
                    try await runCleanup(raw: raw)
                    NSLog("[FlowLocal] Cleanup done")
                } else {
                    NSLog("[FlowLocal] Cleanup disabled, injecting raw text")
                    injector.injectAtCursor(raw)
                }
                state = .idle
            } catch {
                state = .error(error.localizedDescription)
                lastError = error.localizedDescription
                flashErrorThenIdle()
            }
        }
    }

    private func runCleanup(raw: String) async throws {
        let session = injector.makeSession()
        do {
            _ = try await cleanup.clean(
                raw: raw,
                endpoint: settings.ollamaEndpoint,
                model: settings.ollamaModel,
                style: settings.formattingStyle,
                onDelta: { session.feed($0) }
            )
            session.finish()
        } catch {
            // Ollama unavailable or failed: fall back to the raw transcript if nothing pasted yet.
            if session.pastedAny {
                session.finish()
            } else {
                injector.injectAtCursor(raw)
            }
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
