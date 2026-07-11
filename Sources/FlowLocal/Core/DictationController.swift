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
        AudioRecorder.requestMicrophonePermission { _ in }

        if !HotkeyManager.hasAccessibilityPermission {
            HotkeyManager.requestAccessibilityPermission()
        }
        if !hotkey.start() {
            lastError = "Grant Accessibility permission, then relaunch."
        }

        cleanup.warmUp(endpoint: settings.ollamaEndpoint, model: settings.ollamaModel)

        // Load whisper off the main thread; mark ready when done.
        let path = settings.whisperModelPath
        inferenceQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.transcriber.loadModel(at: path)
                Task { @MainActor in self.isReady = true }
            } catch {
                Task { @MainActor in
                    self.lastError = error.localizedDescription
                    self.state = .error(error.localizedDescription)
                }
            }
        }
    }

    /// Re-check the hotkey tap after the user grants Accessibility (from the menu).
    func retryHotkey() {
        if hotkey.start() { lastError = nil }
    }

    // MARK: - Toggle

    func toggle() {
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
                guard !raw.isEmpty else { state = .idle; return }

                if settings.cleanupEnabled {
                    state = .cleaning
                    try await runCleanup(raw: raw)
                } else {
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
