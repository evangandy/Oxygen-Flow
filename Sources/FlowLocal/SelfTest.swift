import AVFoundation
import Foundation

/// Headless pipeline check: load whisper, transcribe a WAV, run Ollama cleanup, print timings.
enum SelfTest {
    static func run(wavPath: String) {
        let settings = AppSettings.shared
        let modelPath = settings.whisperModelPath
        print("== FlowLocal self-test ==")
        print("whisper model: \(modelPath)")
        print("ollama: \(settings.ollamaEndpoint) model=\(settings.ollamaModel)")
        print("wav: \(wavPath)\n")

        guard let samples = readWav16kMono(path: wavPath) else {
            print("ERROR: could not read WAV at \(wavPath)")
            exit(1)
        }
        print("loaded \(samples.count) samples (~\(String(format: "%.1f", Double(samples.count) / 16000))s)")

        let transcriber = Transcriber()
        do {
            var t = Date()
            try transcriber.loadModel(at: modelPath)
            print(String(format: "model load: %.2fs", -t.timeIntervalSinceNow))

            t = Date()
            let raw = try transcriber.transcribe(samples: samples)
            print(String(format: "transcribe: %.2fs", -t.timeIntervalSinceNow))
            print("RAW: \(raw)\n")

            // Cleanup (streaming) with time-to-first-token measurement.
            let cleanup = Cleanup()
            let sem = DispatchSemaphore(value: 0)
            let start = Date()
            var firstToken: TimeInterval?
            Task {
                do {
                    let cleaned = try await cleanup.clean(
                        raw: raw,
                        endpoint: settings.ollamaEndpoint,
                        model: settings.ollamaModel,
                        style: settings.formattingStyle,
                        onDelta: { _ in
                            if firstToken == nil { firstToken = -start.timeIntervalSinceNow }
                        }
                    )
                    if let ft = firstToken {
                        print(String(format: "cleanup first-token: %.2fs", ft))
                    }
                    print(String(format: "cleanup total: %.2fs", -start.timeIntervalSinceNow))
                    print("CLEANED: \(cleaned)")
                } catch {
                    print("cleanup ERROR: \(error.localizedDescription)")
                }
                sem.signal()
            }
            // Pump the main run loop so MainActor deliveries in Cleanup can execute
            // (blocking the main thread outright would deadlock).
            while sem.wait(timeout: .now()) == .timedOut {
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            }
            // Skip C++ static destructors (ggml aborts during teardown); results are already printed.
            fflush(stdout)
            _exit(0)
        } catch {
            print("ERROR: \(error.localizedDescription)")
            exit(1)
        }
        exit(0)
    }

    /// Read a WAV into 16 kHz mono Float32 samples (converts if needed).
    private static func readWav16kMono(path: String) -> [Float]? {
        let url = URL(fileURLWithPath: path)
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let inFormat = file.processingFormat
        guard let inBuffer = AVAudioPCMBuffer(pcmFormat: inFormat,
                                              frameCapacity: AVAudioFrameCount(file.length)) else { return nil }
        do { try file.read(into: inBuffer) } catch { return nil }

        let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                                   channels: 1, interleaved: false)!
        if inFormat.sampleRate == 16_000 && inFormat.channelCount == 1,
           let ch = inBuffer.floatChannelData {
            let n = Int(inBuffer.frameLength)
            return Array(UnsafeBufferPointer(start: ch[0], count: n))
        }

        guard let converter = AVAudioConverter(from: inFormat, to: target) else { return nil }
        let cap = AVAudioFrameCount(Double(file.length) * 16_000 / inFormat.sampleRate + 1024)
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: cap) else { return nil }
        var done = false
        var err: NSError?
        _ = converter.convert(to: outBuffer, error: &err) { _, status in
            if done { status.pointee = .noDataNow; return nil }
            done = true; status.pointee = .haveData; return inBuffer
        }
        guard let ch = outBuffer.floatChannelData else { return nil }
        let n = Int(outBuffer.frameLength)
        return Array(UnsafeBufferPointer(start: ch[0], count: n))
    }
}
