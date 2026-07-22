import AppKit
import ApplicationServices

/// The kind of app the user is dictating into, used to adapt the cleanup formatting.
/// Only three buckets by design: code editors, email, and a generalist default.
enum AppContext: String, CaseIterable {
    case code
    case email
    case general

    /// Display label for the per-context style picker in Settings.
    var label: String {
        switch self {
        case .code: return "Code editors"
        case .email: return "Email"
        case .general: return "Everywhere else"
        }
    }

    /// Formatting guidance injected into the Ollama cleanup system prompt for this context.
    var promptGuidance: String? {
        switch self {
        case .code:
            return """
            CONTEXT: The text is going into a code editor (commit messages, PR descriptions, \
            code comments, or notes to engineers). Make it concise, precise, and technical. \
            Prefer clear, direct phrasing over conversational filler. Preserve any identifiers, \
            file names, or code-like tokens exactly. Do not add greetings or sign-offs.
            """
        case .email:
            return """
            CONTEXT: The text is an email. Use complete sentences and a professional, courteous \
            tone. Add light structure (paragraph breaks) where natural. Only include a greeting \
            or sign-off if the speaker actually dictated one — do not invent names.
            """
        case .general:
            return nil
        }
    }

    /// Detect the context from the frontmost application (call while it's still frontmost).
    static func detect() -> AppContext {
        guard let app = NSWorkspace.shared.frontmostApplication else { return .general }
        let bundle = app.bundleIdentifier ?? ""
        let name = app.localizedName ?? ""

        if isCodeEditor(bundle: bundle, name: name) { return .code }
        if bundle == "com.apple.mail" { return .email }

        if browserBundleIDs.contains(bundle) {
            if let title = frontWindowTitle(pid: app.processIdentifier),
               title.range(of: "gmail", options: .caseInsensitive) != nil {
                return .email
            }
        }
        return .general
    }

    // MARK: - Detection helpers

    private static let codeEditorBundleIDs: Set<String> = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.visualstudio.code.oss",
        "com.todesktop.230313mzl4w4u92",   // Cursor
        "com.apple.dt.Xcode",
        "dev.zed.Zed",
        "com.sublimetext.4",
        "com.sublimetext.3",
    ]

    private static let browserBundleIDs: Set<String> = [
        "com.apple.Safari",
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "company.thebrowser.Browser",       // Arc
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "org.mozilla.firefox",
    ]

    private static func isCodeEditor(bundle: String, name: String) -> Bool {
        if codeEditorBundleIDs.contains(bundle) { return true }
        // Catch JetBrains IDEs and other editors by name.
        let n = name.lowercased()
        return n == "code" || n.contains("cursor") || n.contains("intellij")
            || n.contains("pycharm") || n.contains("webstorm") || n.contains("nova")
    }

    /// Read the focused window title of another app via the Accessibility API.
    private static func frontWindowTitle(pid: pid_t) -> String? {
        let appEl = AXUIElementCreateApplication(pid)
        var windowRef: AnyObject?
        guard AXUIElementCopyAttributeValue(appEl, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let raw = windowRef,
              CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        let window = raw as! AXUIElement
        var titleRef: AnyObject?
        guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success else {
            return nil
        }
        return titleRef as? String
    }
}
