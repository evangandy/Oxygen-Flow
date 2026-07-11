import AppKit
import ApplicationServices
import CoreGraphics

/// Inserts text into whatever app is focused by writing to the pasteboard and synthesizing
/// Cmd+V. Supports a one-shot paste and a progressive (sentence-chunked) streaming session so
/// long dictations appear as they are generated. The original clipboard is restored at the end.
/// When no editable field is focused, callers should fall back to `copyToClipboard` instead.
final class TextInjector {

    private let pasteboard = NSPasteboard.general
    private let vKeyCode: CGKeyCode = 9

    /// Whether the currently focused UI element can accept typed text. Used to decide between
    /// pasting at the cursor and simply copying to the clipboard. Requires Accessibility.
    static func focusedElementIsEditable() -> Bool {
        let system = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let raw = focused,
              CFGetTypeID(raw) == AXUIElementGetTypeID() else { return false }
        let element = raw as! AXUIElement

        var roleValue: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        let role = roleValue as? String
        let editableRoles: Set<String> = [
            kAXTextFieldRole as String,
            kAXTextAreaRole as String,
            kAXComboBoxRole as String,
        ]
        if let role, editableRoles.contains(role) { return true }

        // Web/native rich editors: treat a settable AXValue as editable.
        var settable: DarwinBoolean = false
        if AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success,
           settable.boolValue {
            return true
        }
        return false
    }

    /// Place text on the clipboard for the user to paste manually. Does NOT restore the
    /// previous clipboard — the whole point is that the dictation stays available to paste.
    func copyToClipboard(_ text: String) {
        guard !text.isEmpty else { return }
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// One-shot: paste the whole string, then restore the previous clipboard.
    func injectAtCursor(_ text: String) {
        guard !text.isEmpty else { return }
        let saved = pasteboard.string(forType: .string)
        paste(text)
        // Restore shortly after so the target app has read the pasteboard.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.pasteboard.clearContents()
            if let saved { self.pasteboard.setString(saved, forType: .string) }
        }
    }

    /// A streaming injection: feed token deltas; complete sentences are pasted as they form.
    final class Session {
        private let injector: TextInjector
        private let savedClipboard: String?
        private var buffer = ""
        private(set) var pastedAny = false

        init(injector: TextInjector) {
            self.injector = injector
            self.savedClipboard = NSPasteboard.general.string(forType: .string)
        }

        /// Append a delta; flush any complete sentence(s) to the cursor.
        func feed(_ delta: String) {
            buffer += delta
            guard let idx = lastSentenceBoundary(in: buffer) else { return }
            let chunk = String(buffer[..<idx])
            buffer = String(buffer[idx...])
            flush(chunk)
        }

        /// Paste whatever remains and restore the clipboard.
        func finish() {
            let remaining = buffer.trimmingCharacters(in: .whitespaces)
            if !remaining.isEmpty { flush(remaining) }
            buffer = ""
            let saved = savedClipboard
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                NSPasteboard.general.clearContents()
                if let saved { NSPasteboard.general.setString(saved, forType: .string) }
            }
        }

        private func flush(_ text: String) {
            let piece = pastedAny ? text : text.drop(while: { $0 == " " }).description
            guard !piece.isEmpty else { return }
            injector.paste(piece)
            pastedAny = true
        }

        /// Index just past the last sentence terminator (., !, ?, newline), if any.
        private func lastSentenceBoundary(in s: String) -> String.Index? {
            var found: String.Index?
            var i = s.startIndex
            while i < s.endIndex {
                let c = s[i]
                if c == "." || c == "!" || c == "?" || c == "\n" {
                    found = s.index(after: i)
                }
                i = s.index(after: i)
            }
            return found
        }
    }

    func makeSession() -> Session { Session(injector: self) }

    // MARK: - Low level

    private func paste(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        // Give the pasteboard a beat to settle before the keystroke.
        usleep(6_000)
        sendCmdV()
        usleep(6_000)
    }

    private func sendCmdV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgAnnotatedSessionEventTap)
        up.post(tap: .cgAnnotatedSessionEventTap)
    }
}
