import AppKit
import Combine
import SwiftUI

/// Holds the state the chip should *display*. This lags `DictationController.state` on the way
/// out: when dictation ends we keep showing the last real content while the panel fades, so the
/// capsule never collapses into a bare square before disappearing.
@MainActor
final class ChipPresenter: ObservableObject {
    @Published var state: DictationController.State = .idle
}

/// The floating chip — small, clean, black-and-white with a teal accent. Shows only the live waveform while
/// listening, with a cancel (✕) and confirm (✓) button. No transcript is shown.
struct PillView: View {
    @ObservedObject var controller: DictationController
    @ObservedObject var presenter: ChipPresenter

    var body: some View {
        content
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 6)
            .frame(height: 34)
            .background(
                Capsule(style: .continuous)
                    .fill(Palette.chipBG)
                    .shadow(color: .black.opacity(0.18), radius: 14, y: 5)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Palette.chipRule, lineWidth: 1)
            )
            .fixedSize()
            .animation(.spring(response: 0.34, dampingFraction: 0.82), value: presenter.state)
    }

    private var horizontalPadding: CGFloat {
        if case .listening = presenter.state { return 6 }
        return 13
    }

    @ViewBuilder private var content: some View {
        switch presenter.state {
        case .listening:
            HStack(spacing: 8) {
                ChipButton(system: "xmark", tint: Palette.chipFG.opacity(0.5)) { controller.cancel() }
                Waveform(level: controller.level)
                    .frame(width: 58, height: 24)
                ChipButton(system: "checkmark", tint: .white, filled: true) { controller.toggle() }
            }
        case .transcribing, .cleaning:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).tint(Palette.chipFG)
                Text(presenter.state == .cleaning ? "Formatting" : "Transcribing").chipLabel()
            }
        case .copied:
            HStack(spacing: 7) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                Text("Copied · ⌘V to paste").chipLabel()
            }
        case .error(let msg):
            HStack(spacing: 7) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.danger)
                Text(msg).chipLabel().lineLimit(1).frame(maxWidth: 200)
            }
        case .idle:
            EmptyView()
        }
    }
}

/// A small circular icon button used on the chip.
private struct ChipButton: View {
    let system: String
    var tint: Color
    var filled: Bool = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(filled ? .white : tint)
                .frame(width: 22, height: 22)
                .background(
                    Circle().fill(filled ? AnyShapeStyle(Palette.accent)
                                         : AnyShapeStyle(Palette.chipFG.opacity(hovering ? 0.14 : 0.07)))
                )
                .scaleEffect(hovering ? 1.08 : 1)
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
    }
}

private extension Text {
    func chipLabel() -> some View {
        self.font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(Palette.chipFG.opacity(0.85))
    }
}

/// A lively bar waveform: each bar oscillates on its own phase (a traveling wave) so the chip
/// always has motion, and the amplitude grows with the live input level while speaking.
struct Waveform: View {
    var level: Float
    private let bars = 5
    private let maxH: CGFloat = 22

    var body: some View {
        // A smoothed, floored level so quiet speech still animates and loud speech is capped.
        let lvl = CGFloat(min(1.0, max(0.06, level)))
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<bars, id: \.self) { i in
                    Capsule()
                        .fill(Palette.accent)
                        .frame(width: 3.5, height: height(bar: i, time: t, level: lvl))
                }
            }
        }
    }

    private func height(bar i: Int, time t: Double, level lvl: CGFloat) -> CGFloat {
        let phase = Double(i) * 1.15
        // Two overlaid sines at different speeds give an organic, non-repetitive motion.
        let fast = (sin(t * 9.0 + phase) + 1) / 2
        let slow = (sin(t * 3.3 + phase * 0.7) + 1) / 2
        let wave = fast * 0.7 + slow * 0.3               // 0...1
        let amplitude = 0.16 + lvl * 2.0                 // idle breathing → big when speaking
        let h = 3 + CGFloat(wave) * amplitude * maxH
        return max(3, min(maxH, h))
    }
}

/// Owns the borderless, always-on-top NSPanel and shows/hides it with a clean fade. The chip is
/// interactive only while listening (its buttons accept clicks); otherwise it's click-through.
@MainActor
final class PillWindowController {
    private let panel: NSPanel
    private let controller: DictationController
    private let presenter = ChipPresenter()
    private var cancellables = Set<AnyCancellable>()

    init(controller: DictationController) {
        self.controller = controller

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .screenSaver
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.alphaValue = 0
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false

        let host = NSHostingView(rootView: PillView(controller: controller, presenter: presenter))
        host.translatesAutoresizingMaskIntoConstraints = true
        panel.contentView = host

        controller.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in self?.update(for: state) }
            .store(in: &cancellables)
    }

    private func update(for state: DictationController.State) {
        // Only capture clicks while the ✕/✓ buttons are visible; otherwise stay click-through.
        panel.ignoresMouseEvents = (state != .listening)

        if state == .idle {
            // Keep the last visible content on screen; fade the whole panel out, THEN clear/hide.
            fade(to: 0) { [weak self] in
                guard let self, self.controller.state == .idle else { return }
                self.presenter.state = .idle
                self.panel.orderOut(nil)
            }
        } else {
            presenter.state = state
            panel.orderFrontRegardless()
            fade(to: 1)
            // Size to the freshly-rendered content on the next runloop tick (after SwiftUI lays out),
            // so the capsule is never clipped or briefly square.
            DispatchQueue.main.async { [weak self] in self?.reposition() }
        }
    }

    private func fade(to alpha: CGFloat, completion: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = alpha
        }, completionHandler: completion)
    }

    /// Center the chip near the bottom of whichever screen currently holds the mouse cursor,
    /// so on a multi-monitor setup the chip appears on the screen you're working on.
    private func reposition() {
        guard let host = panel.contentView else { return }
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        guard size.width > 1, size.height > 1 else { return }

        let screen = screenWithMouse()
        let vf = screen.visibleFrame
        let origin = NSPoint(x: vf.midX - size.width / 2, y: vf.minY + 64)
        panel.setFrame(NSRect(origin: origin, size: size), display: true, animate: false)
    }

    private func screenWithMouse() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }
}
