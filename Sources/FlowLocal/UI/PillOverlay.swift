import AppKit
import Combine
import SwiftUI

/// The floating "pill" content: shows listening waveform, processing spinner, or an error flash.
struct PillView: View {
    @ObservedObject var controller: DictationController

    var body: some View {
        HStack(spacing: 12) {
            icon
            content
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(minWidth: 150)
        .background(
            Capsule(style: .continuous)
                .fill(.black.opacity(0.82))
                .overlay(Capsule(style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))
        )
        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
        .fixedSize()
    }

    @ViewBuilder private var icon: some View {
        switch controller.state {
        case .listening:
            Circle().fill(.red).frame(width: 10, height: 10)
                .shadow(color: .red.opacity(0.8), radius: 4)
        case .transcribing, .cleaning:
            ProgressView().controlSize(.small).tint(.white)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
        case .idle:
            EmptyView()
        }
    }

    @ViewBuilder private var content: some View {
        switch controller.state {
        case .listening:
            if !controller.partialTranscript.isEmpty {
                Text(controller.partialTranscript)
                    .pillLabel()
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: 250, alignment: .trailing)
            } else {
                Waveform(level: controller.level)
                    .frame(width: 90, height: 22)
            }
        case .transcribing:
            Text("Transcribing…").pillLabel()
        case .cleaning:
            Text("Formatting…").pillLabel()
        case .error(let msg):
            Text(msg).pillLabel().lineLimit(1).frame(maxWidth: 220)
        case .idle:
            EmptyView()
        }
    }
}

private extension View {
    func pillLabel() -> some View {
        self.font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
    }
}

/// Simple animated bar waveform driven by the live input level.
struct Waveform: View {
    var level: Float
    private let bars = 13
    // Per-bar multipliers give the classic center-weighted shape.
    private static let weights: [CGFloat] = [0.35, 0.5, 0.65, 0.8, 0.95, 1.0, 1.0, 1.0, 0.95, 0.8, 0.65, 0.5, 0.35]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<bars, id: \.self) { i in
                let w = Waveform.weights[i % Waveform.weights.count]
                Capsule()
                    .fill(.white.opacity(0.9))
                    .frame(width: 3, height: barHeight(weight: w))
            }
        }
        .animation(.easeOut(duration: 0.08), value: level)
    }

    private func barHeight(weight: CGFloat) -> CGFloat {
        let base: CGFloat = 3
        let dynamic = CGFloat(level) * 22 * weight
        return max(base, min(22, base + dynamic))
    }
}

/// Owns the borderless, always-on-top, click-through NSPanel and shows/hides it with state.
@MainActor
final class PillWindowController {
    private let panel: NSPanel
    private let controller: DictationController
    private var cancellables = Set<AnyCancellable>()

    init(controller: DictationController) {
        self.controller = controller

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 56),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .screenSaver
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false

        let host = NSHostingView(rootView: PillView(controller: controller))
        host.translatesAutoresizingMaskIntoConstraints = true
        panel.contentView = host

        controller.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in self?.update(for: state) }
            .store(in: &cancellables)

        controller.$partialTranscript
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reposition() }
            .store(in: &cancellables)
    }

    private func update(for state: DictationController.State) {
        if state == .idle {
            panel.orderOut(nil)
        } else {
            reposition()
            panel.orderFrontRegardless()
        }
    }

    private func reposition() {
        panel.layoutIfNeeded()
        let size = panel.contentView?.fittingSize ?? NSSize(width: 200, height: 56)
        panel.setContentSize(size)
        guard let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        let x = vf.midX - size.width / 2
        let y = vf.minY + 90 // hover near the bottom, above the Dock
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
