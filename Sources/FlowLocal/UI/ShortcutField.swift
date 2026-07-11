import AppKit
import SwiftUI

/// A click-to-record shortcut field. Click it, press a key combo, and it captures the
/// virtual key code + modifier flags. Uses a local key-event monitor while recording.
struct ShortcutField: View {
    @Binding var keyCode: Int
    @Binding var modifierFlags: Int

    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(action: toggle) {
            Text(recording ? "Press a shortcut…" : HotkeyFormatting.string(keyCode: keyCode, flags: modifierFlags))
                .font(.system(.body, design: .rounded))
                .frame(minWidth: 96)
                .padding(.horizontal, 6)
                .foregroundStyle(recording ? Color.accentColor : .primary)
        }
        .onDisappear(perform: stop)
    }

    private func toggle() { recording ? stop() : start() }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Escape cancels without changing the shortcut.
            if event.keyCode == 53 { stop(); return nil }
            // Ignore pure modifier presses; require a real key.
            keyCode = Int(event.keyCode)
            modifierFlags = HotkeyFormatting.cgFlagsRawValue(from: event.modifierFlags)
            stop()
            return nil // swallow so the key isn't typed into the field
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
    }
}
