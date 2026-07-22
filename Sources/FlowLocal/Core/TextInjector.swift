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
    private static let cKeyCode: CGKeyCode = 8

    /// The captured selection returned by `captureSelection`.
    struct SelectionCapture {
        let text: String
        let originalClipboard: String?
    }

    /// Copies whatever is currently selected in the frontmost app (via a synthesized Cmd+C) and
    /// returns it, or `nil` if nothing was selected. Used for the "rewrite selected text" command:
    /// Accessibility's `kAXSelectedTextAttribute` is unreliable across web content and third-party
    /// apps, but Cmd+C + reading the pasteboard works everywhere copy/paste already works.
    static func captureSelection() -> SelectionCapture? {
        let pasteboard = NSPasteboard.general
        let original = pasteboard.string(forType: .string)
        let previousChangeCount = pasteboard.changeCount

        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: cKeyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: cKeyCode, keyDown: false)
        else { return nil }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgAnnotatedSessionEventTap)
        up.post(tap: .cgAnnotatedSessionEventTap)

        // Give the target app a moment to write the selection to the pasteboard.
        usleep(120_000)

        // An unchanged change count means Cmd+C was a no-op — nothing was selected.
        guard pasteboard.changeCount != previousChangeCount,
              let text = pasteboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }

        return SelectionCapture(text: text, originalClipboard: original)
    }

    /// Pastes `text` over the still-active selection (from a prior `captureSelection`), then
    /// restores whatever was on the clipboard before the selection was captured.
    func replaceSelection(with text: String, originalClipboard: String?) {
        guard !text.isEmpty else { return }
        paste(text)
        TextInjector.restoreClipboard(originalClipboard)
    }

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
        TextInjector.restoreClipboard(saved)
    }

    /// Restore a previous clipboard value shortly after a paste, once the target app has read it.
    static func restoreClipboard(_ saved: String?) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NSPasteboard.general.clearContents()
            if let saved { NSPasteboard.general.setString(saved, forType: .string) }
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
            TextInjector.restoreClipboard(savedClipboard)
        }

        private func flush(_ text: String) {
            let piece = pastedAny ? text : text.drop(while: { $0 == " " }).description
            guard !piece.isEmpty else { return }
            injector.paste(piece)
            pastedAny = true
        }

        /// Index just past the last sentence terminator (., !, ?, newline), if any.
        private func lastSentenceBoundary(in s: String) -> String.Index? {
            guard let i = s.lastIndex(where: { ".!?\n".contains($0) }) else { return nil }
            return s.index(after: i)
        }
    }

    func makeSession() -> Session { Session(injector: self) }

    /// Synthesize a Return keypress — used for the opt-in "auto-submit" setting so dictating
    /// into a chat box also sends it, the way Wispr Flow's auto-send does.
    func pressReturn() {
        let returnKeyCode: CGKeyCode = 36
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: returnKeyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: returnKeyCode, keyDown: false)
        else { return }
        down.post(tap: .cgAnnotatedSessionEventTap)
        up.post(tap: .cgAnnotatedSessionEventTap)
    }

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
