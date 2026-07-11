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
    /// `language` nil means auto-detect; pass "en" for fastest English decoding.
    func transcribe(samples: [Float], language: String? = "en") throws -> String {
        guard let ctx else { throw TranscriberError.loadFailed("model not loaded") }
        guard !samples.isEmpty else { return "" }

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

        // Language is held for the duration of the call via a C string.
        let result: Int32 = (language.map { lang in
            lang.withCString { cstr -> Int32 in
                params.language = cstr
                return samples.withUnsafeBufferPointer { buf in
                    whisper_full(ctx, params, buf.baseAddress, Int32(buf.count))
                }
            }
        } ?? samples.withUnsafeBufferPointer { buf in
            params.language = nil
            return whisper_full(ctx, params, buf.baseAddress, Int32(buf.count))
        })

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
}
