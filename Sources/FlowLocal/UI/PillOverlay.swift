import AppKit
import Combine
import SwiftUI

/// The floating pill — minimalist, Wispr Flow–inspired overlay.
struct PillView: View {
    @ObservedObject var controller: DictationController
    @State private var glowPulse = false

    var body: some View {
        HStack(spacing: 10) {
            indicator
            content
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minWidth: 120)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.15), .white.opacity(0.05)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
        )
        .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
        .fixedSize()
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: controller.state)
    }

    @ViewBuilder private var indicator: some View {
        switch controller.state {
        case .listening:
            EmptyView()
        case .transcribing, .cleaning:
            ProgressView()
                .controlSize(.small)
                .tint(.white.opacity(0.7))
        case .error:
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.orange)
        case .idle:
            EmptyView()
        }
    }

    @ViewBuilder private var content: some View {
        switch controller.state {
        case .listening:
            if !controller.partialTranscript.isEmpty {
                Text(controller.partialTranscript)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: 280, alignment: .trailing)
                    .animation(.easeOut(duration: 0.15), value: controller.partialTranscript)
            } else {
                Waveform(level: controller.level)
                    .frame(width: 60, height: 16)
            }
        case .transcribing:
            Text("Transcribing")
                .pillLabel()
        case .cleaning:
            Text("Formatting")
                .pillLabel()
        case .error(let msg):
            Text(msg)
                .pillLabel()
                .lineLimit(1)
                .frame(maxWidth: 220)
        case .idle:
            EmptyView()
        }
    }
}

private extension View {
    func pillLabel() -> some View {
        self.font(.system(size: 13, weight: .regular, design: .rounded))
            .foregroundStyle(.white.opacity(0.7))
    }
}

/// Minimal animated bar waveform.
struct Waveform: View {
    var level: Float
    private let bars = 5
    private static let weights: [CGFloat] = [0.5, 0.8, 1.0, 0.8, 0.5]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<bars, id: \.self) { i in
                let w = Waveform.weights[i]
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(.white.opacity(0.6))
                    .frame(width: 2.5, height: barHeight(weight: w))
            }
        }
        .animation(.easeOut(duration: 0.1), value: level)
    }

    private func barHeight(weight: CGFloat) -> CGFloat {
        let base: CGFloat = 3
        let dynamic = CGFloat(level) * 14 * weight
        return max(base, min(16, base + dynamic))
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
