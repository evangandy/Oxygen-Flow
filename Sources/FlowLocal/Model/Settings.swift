import Foundation

/// Formatting presets that swap the Ollama cleanup system prompt.
enum FormattingStyle: String, CaseIterable, Identifiable {
    case formal = "Formal"
    case casual = "Casual"
    case veryCasual = "Very Casual"

    var id: String { rawValue }

    /// Style-specific guidance appended to the cleanup system prompt.
    var promptGuidance: String {
        switch self {
        case .formal:
            return "Enforce standard English grammar. Use proper sentence structure, correct subject-verb agreement, and appropriate punctuation. Do NOT change the speaker's vocabulary or rephrase their ideas. Keep their words, just make them grammatically correct."
        case .casual:
            return "Use a natural, conversational tone. Correct grammar but keep it relaxed. Trailing periods on single sentences may be dropped."
        case .veryCasual:
            return "Use a very casual, texting-style tone. Fix obvious errors only. Drop trailing periods and keep it brief."
        }
    }
}

/// App-wide settings backed by UserDefaults. Observable so the settings window updates live.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    private enum Key {
        static let whisperModelPath = "whisperModelPath"
        static let ollamaEndpoint = "ollamaEndpoint"
        static let ollamaModel = "ollamaModel"
        static let cleanupEnabled = "cleanupEnabled"
        static let formattingStyle = "formattingStyle"
        static let launchAtLogin = "launchAtLogin"
    }

    @Published var whisperModelPath: String {
        didSet { defaults.set(whisperModelPath, forKey: Key.whisperModelPath) }
    }
    @Published var ollamaEndpoint: String {
        didSet { defaults.set(ollamaEndpoint, forKey: Key.ollamaEndpoint) }
    }
    @Published var ollamaModel: String {
        didSet { defaults.set(ollamaModel, forKey: Key.ollamaModel) }
    }
    @Published var cleanupEnabled: Bool {
        didSet { defaults.set(cleanupEnabled, forKey: Key.cleanupEnabled) }
    }
    @Published var formattingStyle: FormattingStyle {
        didSet { defaults.set(formattingStyle.rawValue, forKey: Key.formattingStyle) }
    }
    @Published var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin) }
    }

    private init() {
        whisperModelPath = defaults.string(forKey: Key.whisperModelPath)
            ?? AppSettings.defaultWhisperModelPath()
        ollamaEndpoint = defaults.string(forKey: Key.ollamaEndpoint) ?? "http://127.0.0.1:11434"
        ollamaModel = defaults.string(forKey: Key.ollamaModel) ?? "qwen2.5:3b-instruct"
        cleanupEnabled = defaults.object(forKey: Key.cleanupEnabled) as? Bool ?? true
        formattingStyle = FormattingStyle(rawValue: defaults.string(forKey: Key.formattingStyle) ?? "")
            ?? .formal
        launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
    }

    /// Prefer a model bundled in the .app Resources; otherwise fall back to the repo models dir.
    static func defaultWhisperModelPath() -> String {
        let name = "ggml-large-v3-turbo"
        if let bundled = Bundle.main.path(forResource: name, ofType: "bin") {
            return bundled
        }
        // Dev fallback: the models directory alongside the project.
        let devPath = "\(NSHomeDirectory())/Desktop/WisprFlow/models/\(name).bin"
        return devPath
    }
}
