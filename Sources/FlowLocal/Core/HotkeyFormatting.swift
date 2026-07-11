import AppKit
import CoreGraphics

/// Converts hotkey (virtual key code + modifier flags) to/from display strings and
/// AppKit/CoreGraphics flag types. Shared by the settings recorder and the event tap.
enum HotkeyFormatting {
    /// The modifier bits we care about when matching a shortcut.
    static let relevantFlags: CGEventFlags = [.maskCommand, .maskShift, .maskControl, .maskAlternate]

    /// Convert AppKit modifier flags (from an `NSEvent`) into a `CGEventFlags` rawValue subset.
    static func cgFlagsRawValue(from modifiers: NSEvent.ModifierFlags) -> Int {
        var flags: CGEventFlags = []
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        return Int(flags.rawValue)
    }

    /// A human-readable shortcut string like "⌃~" or "⌥Space".
    static func string(keyCode: Int, flags: Int) -> String {
        let cg = CGEventFlags(rawValue: UInt64(flags))
        var out = ""
        if cg.contains(.maskControl) { out += "⌃" }
        if cg.contains(.maskAlternate) { out += "⌥" }
        if cg.contains(.maskShift) { out += "⇧" }
        if cg.contains(.maskCommand) { out += "⌘" }
        out += keyName(keyCode)
        return out
    }

    /// Best-effort name for a virtual key code (common keys only).
    static func keyName(_ code: Int) -> String {
        switch code {
        case 50: return "~"
        case 49: return "Space"
        case 36: return "Return"
        case 48: return "Tab"
        case 53: return "Esc"
        case 51: return "Delete"
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        default:
            // Map the ANSI letter/number keys via their characters.
            if let ch = HotkeyFormatting.ansiCharacters[code] { return ch.uppercased() }
            return "Key \(code)"
        }
    }

    private static let ansiCharacters: [Int: String] = [
        0: "a", 11: "b", 8: "c", 2: "d", 14: "e", 3: "f", 5: "g", 4: "h", 34: "i",
        38: "j", 40: "k", 37: "l", 46: "m", 45: "n", 31: "o", 35: "p", 12: "q",
        15: "r", 1: "s", 17: "t", 32: "u", 9: "v", 13: "w", 7: "x", 16: "y", 6: "z",
        29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7",
        28: "8", 25: "9",
    ]
}
