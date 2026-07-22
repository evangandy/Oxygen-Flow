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

/// The floating chip — small, flat black capsule, white text/icons. No color, no glass/blur
/// material (that used an `NSVisualEffectView`, an AppKit-bridged effect that rendered
/// unpredictably) — just solid black on white/dark backgrounds. Shows only the live waveform
/// while listening, with a cancel (✕) and confirm (✓) button. No transcript is shown.
struct PillView: View {
    @ObservedObject var controller: DictationController
    @ObservedObject var presenter: ChipPresenter

    var body: some View {
        content
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 5)
            .frame(minHeight: 28)
            .background(
                Capsule(style: .continuous).fill(Palette.chipBG)
            )
            .compositingGroup()
            .shadow(color: .black.opacity(0.28), radius: 10, y: 4)
            .fixedSize()
            .animation(.spring(response: 0.3, dampingFraction: 0.86), value: presenter.state)
    }

    private var horizontalPadding: CGFloat {
        if case .listening = presenter.state { return 5 }
        return 11
    }

    @ViewBuilder private var content: some View {
        switch presenter.state {
        case .listening:
            HStack(spacing: 6) {
                ChipButton(system: "xmark", tint: Palette.chipFG.opacity(0.55)) { controller.cancel() }
                Waveform(level: controller.level)
                    .frame(width: 52, height: 18)
                ChipButton(system: "checkmark", tint: .white, filled: true) { controller.toggle() }
            }
        case .transcribing, .cleaning, .rewriting:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small).tint(Palette.chipFG)
                Text(statusLabel).chipLabel()
            }
        case .copied:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Copied · ⌘V to paste").chipLabel()
            }
        case .rewritten:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Rewrote selection").chipLabel()
            }
        case .error(let msg):
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.danger)
                Text(msg).chipLabel().lineLimit(1).frame(maxWidth: 180)
            }
        case .idle:
            EmptyView()
        }
    }

    private var statusLabel: String {
        switch presenter.state {
        case .cleaning: return "Formatting"
        case .rewriting: return "Rewriting"
        default: return "Transcribing"
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
                // Filled (the confirm button) inverts to black-on-white for a clear, high-
                // contrast affordance against the chip's black background — still strictly
                // monochrome, no accent color.
                .foregroundStyle(filled ? Palette.vastInk : tint)
                .font(.system(size: 9, weight: .bold))
                .frame(width: 18, height: 18)
                .background(
                    Circle().fill(filled ? AnyShapeStyle(.white) : AnyShapeStyle(Palette.chipFG.opacity(hovering ? 0.18 : 0.09)))
                )
                .scaleEffect(hovering ? 1.08 : 1)
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
    }
}

private extension Text {
    func chipLabel() -> some View {
        self.font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(Palette.chipFG.opacity(0.9))
    }
}

/// A compact, continuously-flowing level meter — thin center-weighted bars that rise and fall
/// smoothly with the mic input, closer to Wispr Flow's fluid equalizer than a blocky scroller.
struct Waveform: View {
    var level: Float
    private let barCount = 9
    private let maxH: CGFloat = 18
    private let minH: CGFloat = 2.5

    @State private var history: [CGFloat] = Array(repeating: 0, count: 9)
    private let tick = Timer.publish(every: 0.09, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<barCount, id: \.self) { i in
                Capsule()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 2.5, height: barHeight(history[i]))
            }
        }
        // A gentle, critically-damped spring — smooth rise/fall with no overshoot "bounce".
        .animation(.spring(response: 0.4, dampingFraction: 0.9), value: history)
        .onReceive(tick) { _ in
            history.removeFirst()
            history.append(CGFloat(level))
        }
    }

    private func barHeight(_ v: CGFloat) -> CGFloat {
        // Boost quiet levels (perceptual curve) and use the full height for a big amplitude range.
        let shaped = pow(min(1, v * 1.5), 0.55)
        return minH + shaped * (maxH - minH)
    }
}

/// Owns the borderless, always-on-top NSPanel and shows/hides it with a clean fade. The panel is
/// a fixed, generously-sized transparent canvas — its frame never resizes while visible, only the
/// SwiftUI content inside animates. (Resizing the panel itself to hug the animating content is
/// what previously produced a visible rectangular clip/residue during transitions.) The chip is
/// interactive only while listening (its buttons accept clicks); otherwise it's click-through.
@MainActor
final class PillWindowController {
    private let panel: NSPanel
    private let controller: DictationController
    private let presenter = ChipPresenter()
    private var cancellables = Set<AnyCancellable>()

    /// Generous fixed canvas — big enough for the widest chip content, so the panel frame never
    /// has to change while visible. Content is bottom-anchored and centered within it.
    private let canvasSize = NSSize(width: 360, height: 72)

    init(controller: DictationController) {
        self.controller = controller

        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: canvasSize),
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

        let root = VStack {
            Spacer()
            PillView(controller: controller, presenter: presenter)
                .padding(.bottom, 18)
        }
        .frame(width: canvasSize.width, height: canvasSize.height)

        let host = NSHostingView(rootView: root)
        host.translatesAutoresizingMaskIntoConstraints = true
        host.frame = NSRect(origin: .zero, size: canvasSize)
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
            let wasHidden = panel.alphaValue == 0
            presenter.state = state
            if wasHidden { reposition() }
            panel.orderFrontRegardless()
            fade(to: 1)
        }
    }

    private func fade(to alpha: CGFloat, completion: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = alpha
        }, completionHandler: completion)
    }

    /// Center the fixed canvas near the bottom of whichever screen currently holds the mouse
    /// cursor, so on a multi-monitor setup the chip appears on the screen you're working on.
    /// Called once per appearance (not on every content change) since the canvas never resizes.
    private func reposition() {
        let screen = screenWithMouse()
        let vf = screen.visibleFrame
        let origin = NSPoint(x: vf.midX - canvasSize.width / 2, y: vf.minY + 40)
        panel.setFrame(NSRect(origin: origin, size: canvasSize), display: true, animate: false)
    }

    private func screenWithMouse() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }
}
