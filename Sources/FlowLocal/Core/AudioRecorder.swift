import AVFoundation
import Foundation

/// Captures microphone audio via AVAudioEngine and produces 16 kHz mono Float32 samples
/// (the format whisper.cpp expects). Publishes a live RMS level for the waveform.
final class AudioRecorder: ObservableObject {
    /// Normalized 0...1 input level, updated on the main thread while recording.
    @Published var level: Float = 0

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let targetFormat: AVAudioFormat

    private let sampleQueue = DispatchQueue(label: "flowlocal.audio.samples")
    private var samples: [Float] = []
    private(set) var isRecording = false
    
    /// Optional callback invoked with new audio samples as they arrive in real-time.
    var onAudioChunk: (([Float]) -> Void)?

    init() {
        targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )!
    }

    /// Ask for microphone access (no-op prompt if already granted).
    static func requestMicrophonePermission(_ completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        default:
            completion(false)
        }
    }

    func start() throws {
        guard !isRecording else { return }
        sampleQueue.sync { samples.removeAll(keepingCapacity: true) }

        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else {
            throw NSError(domain: "FlowLocal.Audio", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No audio input available"])
        }
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer)
        }

        engine.prepare()
        try engine.start()
        isRecording = true
    }

    /// Stop recording and return all captured 16 kHz mono samples.
    @discardableResult
    func stop() -> [Float] {
        guard isRecording else { return [] }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        DispatchQueue.main.async { self.level = 0 }
        return sampleQueue.sync { samples }
    }
    
    /// Retrieve the currently accumulated samples without stopping.
    func currentSamples() -> [Float] {
        return sampleQueue.sync { samples }
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        guard let converter else { return }

        // Estimate output capacity from the sample-rate ratio.
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 1024)
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            return
        }

        var consumed = false
        var error: NSError?
        let status = converter.convert(to: outBuffer, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard status != .error, let channel = outBuffer.floatChannelData else { return }
        let frames = Int(outBuffer.frameLength)
        guard frames > 0 else { return }

        let ptr = channel[0]
        var chunk = [Float](repeating: 0, count: frames)
        for i in 0..<frames { chunk[i] = ptr[i] }

        // RMS for the level meter.
        var sumSquares: Float = 0
        for v in chunk { sumSquares += v * v }
        let rms = sqrt(sumSquares / Float(frames))
        let normalized = min(1, rms * 12) // scale up; speech RMS is small
        DispatchQueue.main.async { self.level = normalized }

        sampleQueue.sync { samples.append(contentsOf: chunk) }
        onAudioChunk?(chunk)
    }
}
