import AppKit
import CoreGraphics

/// Installs a system-wide CGEventTap for ~ and fires a toggle callback.
/// Requires Accessibility permission. The matching keyDown is swallowed so no space
/// character reaches the focused app.
final class HotkeyManager {
    /// Called on the main thread each time ~ is pressed.
    var onToggle: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private let tildeKeyCode: CGKeyCode = 50

    /// Whether the process is currently trusted for Accessibility (needed for the tap + injection).
    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Prompt the user to grant Accessibility permission (opens the system dialog once).
    static func requestAccessibilityPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Start listening. Returns false if the tap could not be created (usually missing permission).
    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: HotkeyManager.eventCallback,
            userInfo: refcon
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
        return true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    /// Re-enable the tap if the system disabled it (can happen on timeout/user input flood).
    private func reenable() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            reenable()
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else { return Unmanaged.passUnretained(event) }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        // Option held, and no other primary modifier that would indicate a different shortcut.
        let hasCtrl = flags.contains(.maskControl)
        let noCmd = !flags.contains(.maskCommand)
        let noOption = !flags.contains(.maskAlternate)

        if keyCode == tildeKeyCode && hasCtrl && noCmd && noOption {
            DispatchQueue.main.async { [weak self] in
                self?.onToggle?()
            }
            return nil // swallow the keystroke
        }

        return Unmanaged.passUnretained(event)
    }

    // C-compatible trampoline back into the instance via refcon.
    private static let eventCallback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
        let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
        return manager.handle(type: type, event: event)
    }
}
