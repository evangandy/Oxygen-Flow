import CWhisper
import Foundation

/// Thin Swift wrapper around whisper.cpp. Loads the GGML model once and keeps the context
/// resident (warm) for the whole session so there is no per-dictation load cost.
final class Transcriber {
    enum TranscriberError: Error, LocalizedError {
        case modelNotFound(String)
        case loadFailed(String)
        case inferenceFailed

        var errorDescription: String? {
            switch self {
            case .modelNotFound(let p): return "Whisper model not found at \(p)"
            case .loadFailed(let p): return "Failed to load whisper model at \(p)"
            case .inferenceFailed: return "Transcription failed"
            }
        }
    }

    private var ctx: OpaquePointer?
    private let threads: Int32

    init() {
        threads = Int32(max(4, ProcessInfo.processInfo.activeProcessorCount - 2))
    }

    deinit {
        if let ctx { whisper_free(ctx) }
    }

    var isLoaded: Bool { ctx != nil }

    /// Peak-normalize quiet audio up toward a target level (never attenuates loud speech),
    /// with a capped gain so we don't blow up background noise on true silence.
    static func normalizeGain(_ samples: [Float]) -> [Float] {
        var peak: Float = 0
        for v in samples { let a = abs(v); if a > peak { peak = a } }
        guard peak > 0.0001 else { return samples } // essentially silent — leave as-is
        let targetPeak: Float = 0.7
        let maxGain: Float = 12
        let gain = min(maxGain, max(1, targetPeak / peak))
        guard gain > 1.01 else { return samples }
        return samples.map { $0 * gain }
    }

    /// Load (or reload) the model. Uses the GPU (Metal) by default.
    func loadModel(at path: String) throws {
        guard FileManager.default.fileExists(atPath: path) else {
            throw TranscriberError.modelNotFound(path)
        }
        if let ctx { whisper_free(ctx); self.ctx = nil }

        var cparams = whisper_context_default_params()
        cparams.use_gpu = true
        cparams.flash_attn = true

        guard let newCtx = whisper_init_from_file_with_params(path, cparams) else {
            throw TranscriberError.loadFailed(path)
        }
        ctx = newCtx
    }

    /// Transcribe 16 kHz mono float samples. Synchronous — call off the main thread.
    /// `language` nil means auto-detect; pass "en" for fastest English decoding. `vocabulary` is
    /// an optional comma-separated list of jargon/names (from the personal dictionary) fed to
    /// whisper as `initial_prompt` to bias decoding toward the exact spelling of those terms.
    func transcribe(samples: [Float], language: String? = "en", vocabulary: String = "") throws -> String {
        guard let ctx else { throw TranscriberError.loadFailed("model not loaded") }
        guard !samples.isEmpty else { return "" }

        // Adaptive gain so quiet / whispered speech is picked up as clearly as normal speech.
        let samples = Transcriber.normalizeGain(samples)

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.n_threads = threads
        params.no_timestamps = true
        params.print_progress = false
        params.print_realtime = false
        params.print_special = false
        params.print_timestamps = false
        params.translate = false
        params.suppress_blank = true
        params.temperature = 0
        params.no_context = true
        // Lower the "no speech" threshold so faint/whispered segments aren't dropped as silence.
        params.no_speech_thold = 0.2

        // Language and vocabulary are C strings that must stay alive for the duration of the call.
        let result: Int32 = Transcriber.withOptionalCString(language) { langPtr in
            Transcriber.withOptionalCString(vocabulary.isEmpty ? nil : vocabulary) { promptPtr in
                var p = params
                p.language = langPtr
                p.initial_prompt = promptPtr
                return samples.withUnsafeBufferPointer { buf in
                    whisper_full(ctx, p, buf.baseAddress, Int32(buf.count))
                }
            }
        }

        guard result == 0 else { throw TranscriberError.inferenceFailed }

        let n = whisper_full_n_segments(ctx)
        var text = ""
        for i in 0..<n {
            if let seg = whisper_full_get_segment_text(ctx, i) {
                text += String(cString: seg)
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Runs `body` with `s` as a live `UnsafePointer<CChar>?`, or `nil` if `s` is nil.
    private static func withOptionalCString<R>(_ s: String?, _ body: (UnsafePointer<CChar>?) -> R) -> R {
        guard let s else { return body(nil) }
        return s.withCString(body)
    }
}
