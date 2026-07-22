import CoreGraphics
import Foundation

/// Formatting presets that swap the Ollama cleanup system prompt.
enum FormattingStyle: String, CaseIterable, Identifiable {
    case formal = "Formal"
    case casual = "Casual"
    case veryCasual = "Very Casual"
    case notes = "Notes"

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
        case .notes:
            return "Restructure the transcript into a concise bullet-point list — one idea per line, starting each line with \"- \". Drop filler and connective words entirely rather than keeping them. This is the one mode where reorganizing structure is expected, not just mechanical cleanup."
        }
    }

    /// Notes mode is a real restructure (bullets), not a minimal copy-edit — the base cleanup
    /// prompt's "don't rewrite/reorder" rules would directly contradict it.
    var allowsRestructuring: Bool { self == .notes }
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
        static let rewriteHotkeyKeyCode = "rewriteHotkeyKeyCode"
        static let rewriteHotkeyModifierFlags = "rewriteHotkeyModifierFlags"
        static let voiceCommandsEnabled = "voiceCommandsEnabled"
        static let transcriptionLanguage = "transcriptionLanguage"
        static let autoSubmitEnabled = "autoSubmitEnabled"
        static let toneSampleText = "toneSampleText"
        static let saveHistoryEnabled = "saveHistoryEnabled"
        static let perContextStyle = "perContextStyle"
    }

    /// Every language whisper.cpp can decode (100, matching Wispr Flow's "100+ languages"
    /// claim), plus "auto" (nil to whisper) which detects the spoken language per-dictation at a
    /// small latency cost vs. pinning one. Generated from the `g_lang` table in
    /// vendor/whisper.cpp/src/whisper.cpp.
    static let languageOptions: [(code: String, label: String)] = [
        ("auto", "Auto-detect"),
        ("en", "English"), ("zh", "Chinese"), ("de", "German"), ("es", "Spanish"),
        ("ru", "Russian"), ("ko", "Korean"), ("fr", "French"), ("ja", "Japanese"),
        ("pt", "Portuguese"), ("tr", "Turkish"), ("pl", "Polish"), ("ca", "Catalan"),
        ("nl", "Dutch"), ("ar", "Arabic"), ("sv", "Swedish"), ("it", "Italian"),
        ("id", "Indonesian"), ("hi", "Hindi"), ("fi", "Finnish"), ("vi", "Vietnamese"),
        ("he", "Hebrew"), ("uk", "Ukrainian"), ("el", "Greek"), ("ms", "Malay"),
        ("cs", "Czech"), ("ro", "Romanian"), ("da", "Danish"), ("hu", "Hungarian"),
        ("ta", "Tamil"), ("no", "Norwegian"), ("th", "Thai"), ("ur", "Urdu"),
        ("hr", "Croatian"), ("bg", "Bulgarian"), ("lt", "Lithuanian"), ("la", "Latin"),
        ("mi", "Maori"), ("ml", "Malayalam"), ("cy", "Welsh"), ("sk", "Slovak"),
        ("te", "Telugu"), ("fa", "Persian"), ("lv", "Latvian"), ("bn", "Bengali"),
        ("sr", "Serbian"), ("az", "Azerbaijani"), ("sl", "Slovenian"), ("kn", "Kannada"),
        ("et", "Estonian"), ("mk", "Macedonian"), ("br", "Breton"), ("eu", "Basque"),
        ("is", "Icelandic"), ("hy", "Armenian"), ("ne", "Nepali"), ("mn", "Mongolian"),
        ("bs", "Bosnian"), ("kk", "Kazakh"), ("sq", "Albanian"), ("sw", "Swahili"),
        ("gl", "Galician"), ("mr", "Marathi"), ("pa", "Punjabi"), ("si", "Sinhala"),
        ("km", "Khmer"), ("sn", "Shona"), ("yo", "Yoruba"), ("so", "Somali"),
        ("af", "Afrikaans"), ("oc", "Occitan"), ("ka", "Georgian"), ("be", "Belarusian"),
        ("tg", "Tajik"), ("sd", "Sindhi"), ("gu", "Gujarati"), ("am", "Amharic"),
        ("yi", "Yiddish"), ("lo", "Lao"), ("uz", "Uzbek"), ("fo", "Faroese"),
        ("ht", "Haitian Creole"), ("ps", "Pashto"), ("tk", "Turkmen"), ("nn", "Nynorsk"),
        ("mt", "Maltese"), ("sa", "Sanskrit"), ("lb", "Luxembourgish"), ("my", "Myanmar"),
        ("bo", "Tibetan"), ("tl", "Tagalog"), ("mg", "Malagasy"), ("as", "Assamese"),
        ("tt", "Tatar"), ("haw", "Hawaiian"), ("ln", "Lingala"), ("ha", "Hausa"),
        ("ba", "Bashkir"), ("jw", "Javanese"), ("su", "Sundanese"), ("yue", "Cantonese"),
    ]

    /// Default hotkey: Control+~ (tilde/backtick key = keyCode 50).
    static let defaultHotkeyKeyCode = 50
    static let defaultHotkeyModifierFlags = Int(CGEventFlags.maskControl.rawValue)

    /// Default "rewrite selection" hotkey: Control+Command+R (keyCode 15 = R).
    static let defaultRewriteHotkeyKeyCode = 15
    static let defaultRewriteHotkeyModifierFlags = Int(
        CGEventFlags.maskControl.rawValue | CGEventFlags.maskCommand.rawValue
    )

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
    /// Virtual key code for the "rewrite selected text" hotkey.
    @Published var rewriteHotkeyKeyCode: Int {
        didSet { defaults.set(rewriteHotkeyKeyCode, forKey: Key.rewriteHotkeyKeyCode) }
    }
    /// Required modifier flags for the "rewrite selected text" hotkey.
    @Published var rewriteHotkeyModifierFlags: Int {
        didSet { defaults.set(rewriteHotkeyModifierFlags, forKey: Key.rewriteHotkeyModifierFlags) }
    }

    /// Human-readable shortcut, e.g. "⌃~" or "⌥Space".
    var hotkeyDisplayString: String {
        HotkeyFormatting.string(keyCode: hotkeyKeyCode, flags: hotkeyModifierFlags)
    }
    var rewriteHotkeyDisplayString: String {
        HotkeyFormatting.string(keyCode: rewriteHotkeyKeyCode, flags: rewriteHotkeyModifierFlags)
    }

    /// A system-prompt block anchoring the model to the user's own voice, built from
    /// `toneSampleText`. `nil` when no samples have been provided.
    var toneGuidance: String? {
        let trimmed = toneSampleText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let capped = String(trimmed.prefix(1200))
        return """
        WRITING STYLE SAMPLES: match the speaker's own voice/tone below — word choice, sentence rhythm, and formality level. Do NOT copy their content or topics, only their style.
        ---
        \(capped)
        ---
        """
    }

    /// In-dictation commands: "scratch that", "new paragraph", "new line".
    @Published var voiceCommandsEnabled: Bool {
        didSet { defaults.set(voiceCommandsEnabled, forKey: Key.voiceCommandsEnabled) }
    }
    /// Whisper language code, or "auto" for per-dictation language detection.
    @Published var transcriptionLanguage: String {
        didSet { defaults.set(transcriptionLanguage, forKey: Key.transcriptionLanguage) }
    }
    /// `nil` means auto-detect (passed straight to whisper as no language hint).
    var whisperLanguageCode: String? {
        transcriptionLanguage == "auto" ? nil : transcriptionLanguage
    }
    /// Press Return after pasting a dictation into an editable field — off by default since it's
    /// global (no per-app targeting yet) and would submit forms/newlines everywhere if left on
    /// outside chat-style apps.
    @Published var autoSubmitEnabled: Bool {
        didSet { defaults.set(autoSubmitEnabled, forKey: Key.autoSubmitEnabled) }
    }
    /// Optional pasted writing samples used to anchor the cleanup/rewrite model's voice to the
    /// user's own style (a prompt-engineering approximation of Wispr Flow's tone-learning).
    @Published var toneSampleText: String {
        didSet { defaults.set(toneSampleText, forKey: Key.toneSampleText) }
    }
    /// "Privacy mode" equivalent: everything already stays on-device, but this additionally
    /// skips writing dictations to the on-disk history log at all.
    @Published var saveHistoryEnabled: Bool {
        didSet { defaults.set(saveHistoryEnabled, forKey: Key.saveHistoryEnabled) }
    }

    /// Per-app-category style overrides (Wispr Flow's "Personalized Style" setting — a formality
    /// tier per app, e.g. Very Casual for iMessage, Formal for email). Keyed by `AppContext.rawValue`.
    /// Empty/missing means "use the global `formattingStyle`" for that context.
    @Published var perContextStyle: [String: String] {
        didSet { defaults.set(perContextStyle, forKey: Key.perContextStyle) }
    }

    /// The style to use for a given detected app context: its override if set, else the global default.
    func style(for context: AppContext) -> FormattingStyle {
        guard let raw = perContextStyle[context.rawValue], let style = FormattingStyle(rawValue: raw) else {
            return formattingStyle
        }
        return style
    }

    /// Set (or clear, passing nil) the style override for a context.
    func setStyle(_ style: FormattingStyle?, for context: AppContext) {
        if let style {
            perContextStyle[context.rawValue] = style.rawValue
        } else {
            perContextStyle.removeValue(forKey: context.rawValue)
        }
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
        rewriteHotkeyKeyCode = defaults.object(forKey: Key.rewriteHotkeyKeyCode) as? Int
            ?? AppSettings.defaultRewriteHotkeyKeyCode
        rewriteHotkeyModifierFlags = defaults.object(forKey: Key.rewriteHotkeyModifierFlags) as? Int
            ?? AppSettings.defaultRewriteHotkeyModifierFlags
        voiceCommandsEnabled = defaults.object(forKey: Key.voiceCommandsEnabled) as? Bool ?? true
        transcriptionLanguage = defaults.string(forKey: Key.transcriptionLanguage) ?? "en"
        autoSubmitEnabled = defaults.object(forKey: Key.autoSubmitEnabled) as? Bool ?? false
        toneSampleText = defaults.string(forKey: Key.toneSampleText) ?? ""
        saveHistoryEnabled = defaults.object(forKey: Key.saveHistoryEnabled) as? Bool ?? true
        perContextStyle = defaults.dictionary(forKey: Key.perContextStyle) as? [String: String] ?? [:]
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
