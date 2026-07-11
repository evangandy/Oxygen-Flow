import CoreGraphics
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
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let hotkeyModifierFlags = "hotkeyModifierFlags"
        static let contextAwareFormatting = "contextAwareFormatting"
    }

    /// Default hotkey: Control+~ (tilde/backtick key = keyCode 50).
    static let defaultHotkeyKeyCode = 50
    static let defaultHotkeyModifierFlags = Int(CGEventFlags.maskControl.rawValue)

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
    /// Virtual key code for the dictation toggle hotkey.
    @Published var hotkeyKeyCode: Int {
        didSet { defaults.set(hotkeyKeyCode, forKey: Key.hotkeyKeyCode) }
    }
    /// Required modifier flags (a `CGEventFlags` rawValue subset) for the hotkey.
    @Published var hotkeyModifierFlags: Int {
        didSet { defaults.set(hotkeyModifierFlags, forKey: Key.hotkeyModifierFlags) }
    }
    /// Adapt cleanup formatting to the active app (code editors, Gmail).
    @Published var contextAwareFormatting: Bool {
        didSet { defaults.set(contextAwareFormatting, forKey: Key.contextAwareFormatting) }
    }

    /// Human-readable shortcut, e.g. "⌃~" or "⌥Space".
    var hotkeyDisplayString: String {
        HotkeyFormatting.string(keyCode: hotkeyKeyCode, flags: hotkeyModifierFlags)
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
        hotkeyKeyCode = defaults.object(forKey: Key.hotkeyKeyCode) as? Int
            ?? AppSettings.defaultHotkeyKeyCode
        hotkeyModifierFlags = defaults.object(forKey: Key.hotkeyModifierFlags) as? Int
            ?? AppSettings.defaultHotkeyModifierFlags
        contextAwareFormatting = defaults.object(forKey: Key.contextAwareFormatting) as? Bool ?? true
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
